# Accessibility

QuantumBilling is used by business owners, accountants and their customers,
who open invoice and payment links. Some of them use a keyboard instead of a
mouse, a screen reader, zoom, or high-contrast settings. This page says what
we aim for, what works today, what doesn't yet, and how to tell us about a
problem.

## Our target

We aim to meet **[WCAG 2.2](https://www.w3.org/TR/WCAG22/) Level AA** across
the app, including the public invoice and payment pages.

In India this is also the bar that the Rights of Persons with Disabilities
Act, 2016, the Guidelines for Indian Government Websites (GIGW 3.0) and
IS 17802 point to. It matters if you run QuantumBilling for a public-sector
body.

We have not had a formal audit. This is a target, not a claim that the app
conforms.

## What works today

- **Language and structure.** Pages declare `lang="en"`. Every layout has a
  `<main id="main-content">` landmark.
- **Skip link.** The first <kbd>Tab</kbd> on any page shows **Skip to
  content**, which moves focus past the navigation to the main content.
- **Labelled forms.** Form fields are built with the shared `<.input>`
  component, which ties each `<label>` to its field and shows errors next to
  it.
- **Icon buttons.** Buttons that show only an icon have an `aria-label` or
  hidden (`sr-only`) text.
- **Visible focus.** Buttons and links show a focus outline. Text fields
  darken their border on focus, with at least 3:1 contrast in both themes.
- **Messages.** Flash messages use `role="alert"`, so screen readers announce
  them.
- **Dialogs.** Confirmations use the native `<dialog>` element, which keeps
  focus inside and closes with <kbd>Esc</kbd>.
- **Motion.** Animations and transitions turn off when your system asks for
  reduced motion (`prefers-reduced-motion`).
- **Themes.** Light and dark themes follow your system setting, and you can
  switch them yourself.

## Known gaps

- **PDF invoices are not tagged PDFs.** A screen reader may read them out of
  order. The HTML version of each invoice is the accessible alternative.
- **Dashboard charts** have no text or table alternative yet. The numbers
  behind them are on the Invoices and Clients pages.
- **No full screen-reader pass yet.** Pages have been checked with a keyboard
  but not end to end with NVDA, JAWS or VoiceOver.
- **Colour in the invoice designer.** You can choose invoice colours that
  don't contrast enough. The designer doesn't warn you yet.

If you can help close any of these, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Reporting a problem

Open a [GitHub issue](https://github.com/phravins/QuantumBilling/issues/new)
with the word **accessibility** in the title, or email
<phravin@icloud.com> if you'd rather not post publicly.

It helps to include:

- the page or link, for example the invoice list or a public payment link;
- what you tried to do and what happened;
- your browser, and any assistive technology, such as a screen reader, zoom or
  voice control, with versions if you know them.

We treat an accessibility bug that stops someone from finishing a task, such
as signing in, creating an invoice or paying one, as seriously as any other
bug that blocks that task.

## Contributor checklist

Check these before you open a pull request that changes the UI:

- [ ] **Labels.** Every field uses `<.input>` with a `label`, or has a
      `<label>` tied to it. A placeholder is not a label.
- [ ] **Names for icons and images.** Icon-only buttons and links have an
      `aria-label`. Images have `alt` text, or `alt=""` if they are only
      decoration.
- [ ] **Keyboard.** You can reach and use everything with <kbd>Tab</kbd>,
      <kbd>Shift</kbd>+<kbd>Tab</kbd>, <kbd>Enter</kbd>, <kbd>Space</kbd> and
      <kbd>Esc</kbd>, in a sensible order, and you can always see where focus
      is. Use a `<button>` for actions and a link for navigation, not a
      clickable `<div>`.
- [ ] **Contrast.** Text has at least 4.5:1 contrast (3:1 for large text).
      Borders, icons and focus indicators have at least 3:1. Check both light
      and dark themes.
- [ ] **Not colour alone.** Status, errors and required fields also use text
      or an icon, not only colour.
- [ ] **Changes are announced.** New errors, flashes and loading states can
      be heard by a screen reader, for example with `role="alert"`, `role="status"`
      or `aria-live`.
- [ ] **Landmarks.** New layouts include the `skip_link` component and a
      `<main id="main-content" tabindex="-1">`.
- [ ] **Motion.** New animations respect `prefers-reduced-motion`.
- [ ] **Tested.** You checked the change with a keyboard only and with an
      automated checker such as [axe DevTools](https://www.deque.com/axe/devtools/)
      or Lighthouse. If you can, try a screen reader too: NVDA on Windows, or
      VoiceOver on macOS and iOS.
