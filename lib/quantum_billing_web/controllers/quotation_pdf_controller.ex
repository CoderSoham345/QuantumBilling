defmodule QuantumBillingWeb.QuotationPdfController do
  @moduledoc """
  The quotation as a document, through the invoice pipeline: the quotation is
  rendered as an unsaved invoice (`Quotations.as_document/1`) with its design
  adapted by `InvoiceDoc.QuotationLayout` (titled "Quotation", "Valid Until",
  no payment block).

    * `show/2` - the print page (the browser can save it as PDF)
    * `download/2` - a server-side PDF, or a redirect to the print page when
      no headless browser is installed
  """
  use QuantumBillingWeb, :controller

  alias QuantumBilling.Quotations
  alias QuantumBilling.Templates
  alias QuantumBillingWeb.InvoiceDoc.Extras
  alias QuantumBillingWeb.InvoiceDoc.QuotationLayout
  alias QuantumBillingWeb.InvoicePdfGenerator

  def show(conn, %{"id" => id}) do
    case Quotations.get_quotation(id) do
      nil ->
        not_found(conn)

      quotation ->
        document = Quotations.as_document(quotation)
        {doc, accent, logo} = Templates.document_for(document)
        doc = QuotationLayout.adapt(doc)

        conn
        |> put_view(html: QuantumBillingWeb.InvoicePdfHTML)
        |> put_root_layout(false)
        |> put_layout(false)
        |> render(:show,
          invoice: document,
          doc: doc,
          accent: accent,
          logo: logo,
          extras: Extras.build(document, doc)
        )
    end
  end

  def download(conn, %{"id" => id}) do
    case Quotations.get_quotation(id) do
      nil ->
        not_found(conn)

      quotation ->
        quotation
        |> Quotations.as_document()
        |> InvoicePdfGenerator.generate_pdf(adapt: &QuotationLayout.adapt/1)
        |> case do
          {:ok, pdf} ->
            send_download(conn, {:binary, pdf},
              filename: "Quotation-#{quotation.number}.pdf",
              content_type: "application/pdf"
            )

          {:error, :no_renderer} ->
            conn
            |> put_flash(
              :info,
              "Server-side PDF export is not available here — use your browser's " <>
                "Print › Save as PDF on this page."
            )
            |> redirect(to: ~p"/quotations/#{quotation}/pdf")

          {:error, reason} ->
            conn
            |> put_flash(:error, "That PDF could not be produced (#{inspect(reason)}).")
            |> redirect(to: ~p"/quotations/#{quotation}/pdf")
        end
    end
  end

  defp not_found(conn) do
    conn
    |> put_flash(:error, "That quotation does not exist.")
    |> redirect(to: ~p"/quotations")
  end
end
