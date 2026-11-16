defmodule QuantumBillingWeb.AccessibilityLandmarksTest do
  @moduledoc """
  Every layout offers a "Skip to content" link (WCAG 2.4.1) that lands on a
  `<main>` landmark. One page per layout, plus the public invoice page, which
  renders without one. See ACCESSIBILITY.md.
  """
  use QuantumBillingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import QuantumBilling.AccountsFixtures

  alias QuantumBilling.Invoices.Invoice
  alias QuantumBilling.Repo

  defp assert_skip_link_and_main(view) do
    assert has_element?(view, ~s(a#skip-link[href="#main-content"]))
    assert has_element?(view, ~s(main#main-content[tabindex="-1"]))
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "the app layout (dashboard)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard")
      assert_skip_link_and_main(view)
    end

    test "the focus layout (onboarding)", %{conn: conn, user: user} do
      not_onboarded(user)

      {:ok, view, _html} = live(conn, ~p"/onboarding")
      assert_skip_link_and_main(view)
    end
  end

  test "the auth layout (sign in)", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")
    assert_skip_link_and_main(view)
  end

  test "the legal layout (privacy policy)", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/privacy")
    assert_skip_link_and_main(view)
  end

  test "the public invoice page", %{conn: conn} do
    invoice =
      Repo.insert!(%Invoice{
        invoice_number: "INV-A11Y-1",
        invoice_date: ~D[2026-03-01],
        place_of_supply: "Maharashtra",
        company_state: "Maharashtra",
        client_name: "Zeta Logistics",
        public_token: "tok_a11y_landmarks_1",
        grand_total: 75_000,
        status: "Draft"
      })

    {:ok, view, _html} = live(conn, ~p"/pay/#{invoice.public_token}")
    assert_skip_link_and_main(view)
  end
end
