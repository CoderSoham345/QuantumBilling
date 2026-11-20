defmodule QuantumBilling.Quotations.QuotationItem do
  @moduledoc """
  One quotation line. It has the same fields as `QuantumBilling.Invoices.InvoiceItem`
  and goes through the same changeset, so a line is priced and taxed exactly as
  it would be on an invoice.
  """
  use Ecto.Schema

  alias QuantumBilling.Invoices.InvoiceItem
  alias QuantumBilling.Money.Paise

  schema "quotation_items" do
    field :description, :string
    field :hsn_sac, :string
    field :quantity, :decimal, default: Decimal.new(1)
    field :unit, :string, default: "Nos"
    field :rate, Paise, default: 0
    field :tax_rate, :integer, default: 18
    # VAT snapshot of the chosen rate.
    belongs_to :tax_rate_ref, QuantumBilling.TaxRates.TaxRate, foreign_key: :tax_rate_id
    field :tax_rate_bp, :integer
    field :tax_category, :string
    field :tax_name, :string
    field :amount, :integer, default: 0
    field :position, :integer, default: 0

    belongs_to :quotation, QuantumBilling.Quotations.Quotation

    # Quotations carry no custom field values yet; the column keeps parity with invoices.
    field :custom_fields, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  The invoice item changeset, applied to a quotation line. `tax` is `:gst` or
  `{:vat, rates_by_id}`. Custom field values are not accepted on quotations.
  """
  def changeset(item, attrs, tax \\ :gst) do
    InvoiceItem.changeset(item, drop_custom_fields(attrs), [], tax)
  end

  defp drop_custom_fields(attrs) when is_map(attrs),
    do: Map.drop(attrs, ["custom_fields", :custom_fields])

  defp drop_custom_fields(attrs), do: attrs
end
