defmodule QuantumBilling.Quotations do
  @moduledoc """
  Quotations (estimates) and their conversion into invoices.

  A quotation is priced and taxed exactly as an invoice (`Invoice.recalculate/1`
  over the same item changeset) and numbered from its own series
  (`quotation_prefix`/`quotation_next_number`), taken in the same transaction
  as the insert. Quotations live in their own table, so no tax figure, GST
  report or GSTR-1 ever reads them.

  Status moves Draft → Sent → Accepted or Declined. Expired is derived (see
  `Quotation.effective_status/2`). An Accepted quotation converts into one
  invoice through `Invoices.create_invoice/2` with `quotation_id:`.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias QuantumBilling.Accounts.Scope
  alias QuantumBilling.Audit
  alias QuantumBilling.Compliance
  alias QuantumBilling.Invoices
  alias QuantumBilling.Invoices.Invoice
  alias QuantumBilling.Invoices.InvoiceItem
  alias QuantumBilling.Money
  alias QuantumBilling.Paging
  alias QuantumBilling.Quotations.Quotation
  alias QuantumBilling.Quotations.QuotationItem
  alias QuantumBilling.Repo
  alias QuantumBilling.Settings
  alias QuantumBilling.Settings.Organization

  # Allowlisted: the sort field comes from the browser.
  @sortable %{
    number: :number,
    client: :client_name,
    quotation_date: :quotation_date,
    valid_until: :valid_until,
    amount: :grand_total
  }

  @default_per_page 10
  @max_per_page 200

  @doc "How long a new quotation stays valid by default, in days."
  def default_validity_days, do: 30

  @doc "Today where the business is: the day Expired is judged against."
  def today, do: Compliance.local_date()

  @doc "The columns the list page may sort on."
  def sortable_fields, do: Map.keys(@sortable)

  @doc """
  One page of quotations, newest first by default, with `:invoice` preloaded.

  Options: `:search` (number or client), `:status` (Draft, Sent, Accepted,
  Declined or Expired; Draft and Sent leave the expired ones out), `:today`,
  `:sort_field`, `:sort_dir`, `:page`, `:per_page`, `:count`.
  """
  def page(opts \\ []) do
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> clamp(1, @max_per_page)
    sort_field = Keyword.get(opts, :sort_field, :quotation_date)
    sort_dir = Keyword.get(opts, :sort_dir, :desc)
    today = Keyword.get_lazy(opts, :today, &today/0)

    result =
      Quotation
      |> search_where(Keyword.get(opts, :search))
      |> status_where(Keyword.get(opts, :status), today)
      |> Paging.page(&order(&1, sort_field, sort_dir),
        page: Keyword.get(opts, :page, 1),
        per_page: per_page,
        count: Keyword.get(opts, :count, false)
      )

    %{result | rows: Repo.preload(result.rows, :invoice)}
  end

  @doc "How many quotations show each status on `today`, Expired included."
  def status_counts(today \\ today()) do
    shown =
      from q in Quotation,
        select: %{
          status:
            fragment(
              "CASE WHEN ? IN ('Draft', 'Sent') AND ? < ? THEN 'Expired' ELSE ? END",
              q.status,
              q.valid_until,
              type(^today, :date),
              q.status
            )
        }

    from(s in subquery(shown), group_by: s.status, select: {s.status, count()})
    |> Repo.all()
    |> Map.new()
  end

  defp search_where(query, blank) when blank in [nil, ""], do: query

  defp search_where(query, search) do
    pattern = "%" <> String.trim(search) <> "%"
    where(query, [q], ilike(q.number, ^pattern) or ilike(q.client_name, ^pattern))
  end

  defp status_where(query, status, _today) when status in [nil, "", "All", "All Status"],
    do: query

  defp status_where(query, "Expired", today) do
    where(query, [q], q.status in ["Draft", "Sent"] and q.valid_until < ^today)
  end

  defp status_where(query, status, today) when status in ["Draft", "Sent"] do
    where(query, [q], q.status == ^status and q.valid_until >= ^today)
  end

  defp status_where(query, status, _today), do: where(query, [q], q.status == ^status)

  defp order(query, field, direction) do
    column = Map.get(@sortable, field, :quotation_date)
    direction = if direction == :asc, do: :asc, else: :desc

    # The id breaks ties so paging is stable.
    order_by(query, [q], [{^direction, field(q, ^column)}, {^direction, q.id}])
  end

  defp clamp(value, minimum, maximum) when is_integer(value),
    do: value |> max(minimum) |> min(maximum)

  defp clamp(_value, minimum, _maximum), do: minimum

  @doc "Fetches a quotation with its lines and any linked invoice, or `nil`."
  def get_quotation(id) do
    case Integer.parse(to_string(id)) do
      {int_id, ""} -> Quotation |> Repo.get(int_id) |> with_assocs()
      _not_an_id -> nil
    end
  end

  @doc "As `get_quotation/1`, but raises when missing."
  def get_quotation!(id) do
    get_quotation(id) || raise Ecto.NoResultsError, queryable: Quotation
  end

  defp with_assocs(nil), do: nil

  defp with_assocs(%Quotation{} = quotation) do
    Repo.preload(
      quotation,
      [items: from(i in QuotationItem, order_by: i.position), invoice: []],
      force: true
    )
  end

  @doc "Builds a changeset for the quotation form."
  def change_quotation(%Quotation{} = quotation \\ %Quotation{}, attrs \\ %{}, trusted \\ %{}) do
    Quotation.changeset(quotation, attrs, trusted)
  end

  @doc """
  The company and tax settings a new quotation would take, for the form's
  live preview. An existing quotation previews only the company.
  """
  def preview_trusted(%Organization{} = organization, %Quotation{id: nil}) do
    organization
    |> Invoices.company_snapshot()
    |> Map.merge(Organization.invoice_tax_snapshot(organization))
  end

  def preview_trusted(%Organization{} = organization, %Quotation{}),
    do: Invoices.company_snapshot(organization)

  @doc "Creates a quotation with the next number in the quotation series."
  def create_quotation(%Scope{} = scope, attrs) do
    # Outside the transaction, as for invoices: these reads must not deadlock.
    _organization = Settings.ensure_organization()
    template = Invoices.resolve_template(attrs)

    Multi.new()
    # Locked so two transactions cannot take the same number.
    |> Multi.run(:organization, fn repo, _changes ->
      case repo.one(from o in Organization, order_by: [asc: o.id], limit: 1, lock: "FOR UPDATE") do
        nil -> {:ok, %Organization{}}
        organization -> {:ok, organization}
      end
    end)
    |> Multi.insert(:quotation, fn %{organization: locked} ->
      trusted =
        %{number: Settings.next_quotation_number(locked), user_id: scope.user.id}
        |> Map.merge(Invoices.company_snapshot(locked))
        |> Map.merge(Invoices.layout_snapshot(template))
        |> Map.put(:default_currency, Organization.currency_code(locked))
        |> Map.merge(Organization.invoice_tax_snapshot(locked))

      Quotation.changeset(%Quotation{}, attrs, trusted)
    end)
    |> Multi.run(:advance_number, fn repo, %{organization: organization} ->
      organization
      |> Ecto.Changeset.change(%{
        quotation_next_number: (organization.quotation_next_number || 1) + 1
      })
      |> repo.insert_or_update()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{quotation: quotation}} ->
        audit(:create_quotation, quotation, scope)
        {:ok, with_assocs(quotation)}

      {:error, :quotation, changeset, _changes} ->
        {:error, changeset}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a Draft or Sent quotation; an Accepted or Declined one is locked
  (`{:error, :locked}`). The number and company block never change; the
  design is re-taken from the form.
  """
  def update_quotation(%Scope{} = scope, %Quotation{} = quotation, attrs) do
    if Quotation.editable?(quotation) do
      trusted = attrs |> Invoices.resolve_template() |> Invoices.layout_snapshot()

      quotation
      |> Repo.preload(:items)
      |> Quotation.changeset(attrs, trusted)
      |> Repo.update()
      |> case do
        {:ok, quotation} ->
          audit(:update_quotation, quotation, scope)
          {:ok, with_assocs(quotation)}

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error, :locked}
    end
  end

  @doc "Draft → Sent. An expired draft needs a later `valid_until` first."
  def mark_sent(%Scope{} = scope, %Quotation{} = quotation) do
    transition(scope, quotation, "Sent", :quotation_sent, fn q ->
      q.status == "Draft" and not expired?(q)
    end)
  end

  @doc "Draft or Sent → Accepted. An expired quotation needs a later `valid_until` first."
  def accept(%Scope{} = scope, %Quotation{} = quotation) do
    transition(scope, quotation, "Accepted", :quotation_accepted, fn q ->
      q.status in ["Draft", "Sent"] and not expired?(q)
    end)
  end

  @doc "Draft or Sent (expired or not) → Declined."
  def decline(%Scope{} = scope, %Quotation{} = quotation) do
    transition(scope, quotation, "Declined", :quotation_declined, fn q ->
      q.status in ["Draft", "Sent"]
    end)
  end

  defp transition(scope, quotation, status, action, allowed?) do
    # Re-read under a lock: the page may be showing a stale status.
    Repo.transaction(fn ->
      current =
        Repo.one(from q in Quotation, where: q.id == ^quotation.id, lock: "FOR UPDATE")

      cond do
        is_nil(current) ->
          Repo.rollback(:not_found)

        allowed?.(current) ->
          case current |> Quotation.status_changeset(status) |> Repo.update() do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end

        true ->
          Repo.rollback(:invalid_transition)
      end
    end)
    |> case do
      {:ok, updated} ->
        audit(action, updated, scope)
        {:ok, with_assocs(updated)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp expired?(quotation), do: Quotation.effective_status(quotation, today()) == "Expired"

  @doc "Deletes a quotation for good, unless it has been converted (`{:error, :converted}`)."
  def delete_quotation(%Scope{} = scope, %Quotation{} = quotation) do
    quotation = Repo.preload(quotation, :invoice, force: true)

    if Quotation.converted?(quotation) do
      {:error, :converted}
    else
      case Repo.delete(quotation) do
        {:ok, deleted} ->
          audit(:delete_quotation, deleted, scope)
          {:ok, deleted}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  @doc "Whether the quotation can be converted: Accepted, with no invoice yet."
  def convertible?(%Quotation{status: "Accepted"} = quotation) do
    not Quotation.converted?(Repo.preload(quotation, :invoice))
  end

  def convertible?(%Quotation{}), do: false

  @doc """
  The new-invoice form's params for converting `quotation`: client, place of
  supply, currency, design, remarks, terms and lines. Dates come from the
  invoice form's own defaults.
  """
  def invoice_params(%Quotation{} = quotation) do
    quotation = Repo.preload(quotation, :items)

    %{
      "client_id" => (quotation.client_id && to_string(quotation.client_id)) || "",
      "client_name" => quotation.client_name,
      "client_gstin" => quotation.client_gstin,
      "client_pan" => quotation.client_pan,
      "client_billing_address" => quotation.client_billing_address,
      "client_email" => quotation.client_email,
      "client_state" => quotation.client_state,
      "client_city" => quotation.client_city,
      "client_pincode" => quotation.client_pincode,
      "client_tax_number" => quotation.client_tax_number,
      "place_of_supply" => quotation.place_of_supply,
      "currency" => quotation.currency,
      "reverse_charge" => to_string(quotation.reverse_charge == true),
      "remarks" => quotation.remarks,
      "terms" => quotation.terms,
      "items" =>
        quotation.items
        |> Enum.sort_by(& &1.position)
        |> Enum.with_index()
        |> Map.new(fn {item, index} -> {to_string(index), item_params(item, index)} end)
    }
    |> maybe_put("template_id", quotation.template_id)
  end

  defp item_params(%QuotationItem{} = item, index) do
    %{
      "description" => item.description,
      "hsn_sac" => item.hsn_sac,
      "quantity" => Decimal.to_string(item.quantity, :normal),
      "unit" => item.unit,
      "rate" => Money.to_input(item.rate),
      "tax_rate" => to_string(item.tax_rate),
      "position" => to_string(index)
    }
    |> maybe_put("tax_rate_id", item.tax_rate_id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_string(value))

  @doc """
  The quotation as an unsaved invoice, only for rendering its PDF with the
  invoice designs. Never inserted.
  """
  def as_document(%Quotation{} = quotation) do
    quotation = Repo.preload(quotation, :items)

    %Invoice{
      invoice_type: "Quotation",
      invoice_number: quotation.number,
      invoice_date: quotation.quotation_date,
      due_date: quotation.valid_until,
      place_of_supply: quotation.place_of_supply,
      status: nil,
      currency: quotation.currency,
      client_id: quotation.client_id,
      client_name: quotation.client_name,
      client_gstin: quotation.client_gstin,
      client_pan: quotation.client_pan,
      client_billing_address: quotation.client_billing_address,
      client_email: quotation.client_email,
      client_state: quotation.client_state,
      client_city: quotation.client_city,
      client_pincode: quotation.client_pincode,
      client_tax_number: quotation.client_tax_number,
      company_name: quotation.company_name,
      company_address: quotation.company_address,
      company_gstin: quotation.company_gstin,
      company_state: quotation.company_state,
      company_tax_number: quotation.company_tax_number,
      tax_regime: quotation.tax_regime,
      reverse_charge: quotation.reverse_charge,
      prices_include_tax: quotation.prices_include_tax,
      round_to_whole_units: quotation.round_to_whole_units,
      total_items: quotation.total_items,
      total_quantity: quotation.total_quantity,
      taxable_value: quotation.taxable_value,
      cgst_amount: quotation.cgst_amount,
      sgst_amount: quotation.sgst_amount,
      igst_amount: quotation.igst_amount,
      cess_amount: quotation.cess_amount,
      vat_amount: quotation.vat_amount,
      tax_breakdown: quotation.tax_breakdown,
      round_off: quotation.round_off,
      grand_total: quotation.grand_total,
      remarks: quotation.remarks,
      terms: quotation.terms,
      template_id: quotation.template_id,
      layout_xml: quotation.layout_xml,
      custom_fields: %{},
      items: Enum.map(quotation.items, &as_invoice_item/1)
    }
  end

  defp as_invoice_item(%QuotationItem{} = item) do
    %InvoiceItem{
      description: item.description,
      hsn_sac: item.hsn_sac,
      quantity: item.quantity,
      unit: item.unit,
      rate: item.rate,
      tax_rate: item.tax_rate,
      tax_rate_id: item.tax_rate_id,
      tax_rate_bp: item.tax_rate_bp,
      tax_category: item.tax_category,
      tax_name: item.tax_name,
      amount: item.amount,
      position: item.position,
      custom_fields: %{}
    }
  end

  defp audit(action, %Quotation{} = quotation, %Scope{} = scope) do
    Audit.log_event(action, "Quotation", quotation.id,
      user_id: scope.user && scope.user.id,
      details: %{
        number: quotation.number,
        client_name: quotation.client_name,
        status: quotation.status,
        grand_total: quotation.grand_total
      }
    )
  end
end
