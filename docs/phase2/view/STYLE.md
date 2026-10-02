# Style hand-off: Bootstrap 3.3.7 to 5.3

How the Phase 1 look translates to the Phase 2 Angular view. Derived from the class attributes in the legacy pages
(`master-antique-repair/MasterAntiqueRepair/MasterAntiqueRepair/Account/*.aspx`, `*.aspx`, `Site.master`), the classes
set in code-behind (`App_Code/UiHelpers.cs`, `TicketDetailView.aspx.cs`), `Content/Site.css` and `Bundle.config`. The
legacy app uses **Bootstrap 3.3.7** (`Content/bootstrap.css` header; `packages.config`: `bootstrap` and
`AspNet.ScriptManager.bootstrap` 3.3.7). Page numbers refer to `VIEW.md`.

## Target

- **Bootstrap 5.3** (CSS only), **Bootstrap Icons**, **ng-bootstrap** for interactive components.
- All from npm, bundled and version-pinned. No jQuery, no Bootstrap JavaScript bundle, no CDN.
- Bootstrap's default theme. The legacy app loads only `bootstrap.css` and `Site.css` (`Bundle.config`); the gradient
  `bootstrap-theme.css` is present but never loaded.

## Class mapping

Counts are occurrences in the page and master markup, plus code-behind where noted.

### Classes that change

| Bootstrap 3 | Count | Where | Bootstrap 5.3 |
|---|---|---|---|
| `panel` | 9 | 9 ManagerView card, 10 | `card` |
| `panel-default` | 9 | as `panel` | (none; `card` is the default) |
| `panel-heading` | 9 | as `panel` | `card-header` |
| `panel-title` | 2 | 9 | `card-title` (inside the accordion header) |
| `panel-body` | 9 | as `panel` | `card-body` |
| `panel-collapse` | 2 | 9 | ng-bootstrap accordion body |
| `panel-title-toggle` (custom) | 2 | 9 | ng-bootstrap accordion button (`accordion-button`) |
| `glyphicon` | 9 | 2, 4, 7, 9, header | `bi` (Bootstrap Icons, see Icons) |
| `glyphicon-*` | 9 | as `glyphicon` | `bi-*` (see Icons) |
| `form-group` | 45 | forms | `mb-3` (in inline forms: a `col-auto`) |
| `control-label` | 23 | horizontal forms | `col-form-label` (with the column class) |
| `form-horizontal` | 9 | 1, 2, 3, 4, 9, 11 | each field a `row mb-3`: label `col-md-N col-form-label`, input wrapper `col-md-M` |
| `form-inline` | 5 | 5, 12 | `row g-2 align-items-end` with each field in `col-auto` |
| `help-block` | 2 | 9 | `form-text`, tied with `aria-describedby` |
| `col-md-offset-2` | 3 | 1, 3, 11 | `offset-md-2` |
| `col-md-offset-3` | 2 | 2, 4 | `offset-md-3` |
| `col-md-offset-4` | 4 | 9 | `offset-md-4` |
| `btn-default` | 5 | 2, 6, 7, 8 | `btn-secondary` (`btn-outline-secondary` beside a primary button: Cancel in modals, Log In on page 7) |
| `btn-xs` | 1 | 5 | `btn-sm` (no extra-small size in 5) |
| `table-condensed` | 6 | 9, 10, 12 | `table-sm` |
| `dl-horizontal` | 3 | 12 | `dl class="row"`, `dt class="col-sm-3"`, `dd class="col-sm-9"` |
| `label` | 7 + 1 code-behind | status and Deleted badges: 6, 8, 9, 12 | `badge` |
| `label-default` | 2 + 1 code-behind | Deleted badge (12); unknown state | `text-bg-secondary` |
| `label-warning` | code-behind | SUBMITTED | `text-bg-warning` |
| `label-info` | code-behind | INPROGRESS | `text-bg-info` |
| `label-success` | code-behind | COMPLETED | `text-bg-success` |
| `jumbotron` | 1 | 7 | removed in 5: `p-5 mb-4 rounded-3` |
| `bg-primary` (on the jumbotron) | 1 | 7 | `text-bg-primary` |
| `navbar-inverse` | 1 | header | `navbar-dark bg-dark` (or `data-bs-theme="dark"` on the navbar) |
| `navbar-fixed-top` | 1 | header | `fixed-top` |
| `navbar-header` | 1 | header | removed; brand and toggler sit directly in the container |
| `navbar-toggle` | 1 | header | `navbar-toggler` |
| `icon-bar` | 3 | header | one `span class="navbar-toggler-icon"` |
| `navbar-right` | 1 | header | `ms-auto` on the right-hand `navbar-nav` |
| `navbar-nav` (items) | 2 | header | add `nav-item` to each `li` and `nav-link` to each link |
| `nav-stacked` | 1 | 12 | `flex-column` |
| `close` | 3 | modals 6, 8 | `btn-close` with `aria-label="Close"` (no `&times;` child) |
| `active` on `li` (code-behind) | 4 | 12 tabs | `active` on the `nav-link` (ng-bootstrap nav sets it) |
| `tab-pane` (code-behind) | 4 | 12 | ng-bootstrap nav content |
| `collapse` | 3 | 9 panels, header | ng-bootstrap `ngbCollapse` / accordion; the navbar's `collapse navbar-collapse` stays |
| `fade`, `modal`, `modal-dialog`, `modal-content`, `modal-header`, `modal-title`, `modal-body`, `modal-footer` | 3 each | 6, 8 | ng-bootstrap `NgbModal` renders its own; keep `modal-header`, `modal-title`, `modal-body`, `modal-footer` inside the template |
| `popover-toggle` (custom) + `data-toggle="popover"` | 7 | 6, 8, 12 | `button class="btn btn-link p-0 text-start"` with `ngbPopover` (trigger: click and focus) |

### Classes that do not change

`btn` (33), `btn-primary` (17), `btn-success` (5), `btn-info` (2), `btn-danger` (2), `btn-link` (2), `btn-sm` (4),
`btn-lg` (3), `table` (11), `row` (8), `container` (2), `col-md-2` (6), `col-md-3` (3), `col-md-4` (17), `col-md-6`
(6), `col-md-8` (21), `col-md-9` (5), `col-md-10` (9), `col-sm-3` (1), `col-sm-9` (1), `form-control` (36; selects
become `form-select`), `text-danger` (27), `text-success` (6), `text-muted` (2; `text-body-secondary` is the 5.3 name,
`text-muted` still works), `text-primary` (1), `text-info` (1), `text-center` (5), `lead` (1), `nav` (3), `nav-pills`
(1), `navbar` (1), `navbar-brand` (1), `navbar-collapse` (1), `navbar-text` (1), `tab-content` (1), `body-content`
(1, custom, see Custom CSS).

**Selects**: the legacy `asp:DropDownList` uses `form-control`; in 5.3 a `select` uses `form-select`.

### Inline styles in the legacy markup

| Legacy | Where | 5.3 |
|---|---|---|
| `style="margin-bottom: 15px;"` on inline forms | 5, 12 | `mb-3` |
| `style="margin-left: 20px;"` on a form group | 5, 12 | `ms-md-3` |
| `style="height: 330px; overflow-y: auto;"` on card bodies | 10 | custom class `.metrics-scroll` (keep 330 px) |
| `style="height: 330px;"` on pie chart card bodies | 10 | custom class `.metrics-pie` (keep 330 px) |
| `<col>` widths 60, 120, 110, 140, 160, 80 px | 9, 12 | keep as `col` widths in the fixed-layout tables |
| canvas `height="55"` (line and bar charts), `300 x 300` (pies) | 10 | keep the aspect: line and bar charts responsive, pies fixed 300 px |

## Interactive components

| Page | Legacy component | ng-bootstrap replacement |
|---|---|---|
| header | navbar collapse (`data-toggle="collapse"`) | `ngbCollapse` on the navbar content, toggler button with `aria-controls`, `aria-expanded`, label "Toggle navigation" |
| 6 My repairs | modal "Add Comment" | `NgbModal` |
| 6, 8, 12 | comment popovers (`data-trigger="focus"`) | `ngbPopover` on a `button`, triggers click and focus, closes on blur and Escape |
| 8 My tickets | modals "Complete Repair" and "Add Comment" | `NgbModal` |
| 9 Administration | two collapsible panels, collapsed by default, chevron rotates when open | `ngbAccordion`, both items closed at start, independent (not "close others") |
| 9 Administration | `confirm()` before delete | `NgbModal` confirmation with "Cancel" (`btn-outline-secondary`) and "Delete" (`btn-danger`) |
| 12 Search | vertical pills (`data-toggle="pill"`) | `ngbNav` with `nav-pills flex-column`, orientation vertical |
| 10 Metrics | Chart.js 4.4.0 canvases | Chart.js 4 from npm (directly or through `ng2-charts`) |

## Icons

Bootstrap Icons from npm (`bootstrap-icons`), used as `<i class="bi bi-NAME" aria-hidden="true"></i>`.

| Page | Glyphicon | Bootstrap Icons | Use |
|---|---|---|---|
| header | `glyphicon-wrench` | `bi-wrench` | decorative (the link text "Home" names it) |
| 2 Forgot password | `glyphicon-info-sign` | `bi-info-circle` | decorative (text follows) |
| 4 Reset password | `glyphicon-ok` | `bi-check-lg` | decorative (text follows) |
| 7 Home | `glyphicon-wrench` (hero heading) | `bi-wrench` | decorative |
| 7 Home | `glyphicon-inbox` | `bi-inbox` | decorative (column title follows) |
| 7 Home | `glyphicon-wrench` (Repair column) | `bi-wrench` | decorative |
| 7 Home | `glyphicon-ok-circle` | `bi-check-circle` | decorative |
| 9 Administration | `glyphicon-chevron-down` (2) | `bi-chevron-down` (ng-bootstrap accordion draws its own; drop the icon) | decorative |

No icon in the legacy app carries meaning on its own, so none needs a text label.

## Status badges

From `UiHelpers.StatusLabelClass`; the badge text is the state name.

| State | Legacy | 5.3 |
|---|---|---|
| SUBMITTED | `label label-warning` | `badge text-bg-warning` |
| INPROGRESS | `label label-info` | `badge text-bg-info` |
| COMPLETED | `label label-success` | `badge text-bg-success` |
| other | `label label-default` | `badge text-bg-secondary` |
| Deleted (page 12) | `label label-default` | `badge text-bg-secondary` |

The `text-bg-*` classes pick a readable text colour for each background, which keeps the badges at AA contrast.

## Chart colours

Legacy Metrics uses the Bootstrap 3 palette in this order: `#337ab7`, `#5cb85c`, `#f0ad4e`, `#d9534f`, `#5bc0de`,
`#292b2c`, repeated per employee or commenter, the same index giving the same colour in the line and bar charts. Phase
2 uses the Bootstrap 5.3 equivalents in the same order: `#0d6efd` (primary), `#198754` (success), `#ffc107`
(warning), `#dc3545` (danger), `#0dcaf0` (info), `#212529` (dark), and keeps the same-index rule. Pie slices have white
borders.

## Custom CSS

`Content/Site.css`, verbatim:

```css
/* Move down content because we have a fixed navbar that is 50px tall */
/* Also: sticky footer - body/form/.body-content form a flex column so the
   footer stays pinned to the bottom of the viewport even on short pages,
   instead of floating up directly under sparse content. */
body {
    padding-top: 50px;
    padding-bottom: 20px;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
}

body > form {
    display: flex;
    flex-direction: column;
    flex: 1;
}

/* Wrapping element */
/* Set some basic padding to keep content from hitting the edges */
.body-content {
    padding-left: 15px;
    padding-right: 15px;
    display: flex;
    flex-direction: column;
    flex: 1;
}

.body-content footer {
    margin-top: auto;
    padding-top: 20px;
}

/* Set widths on the form inputs since otherwise they're 100% wide */
input,
select,
textarea {
    max-width: 280px;
}

/* Responsive: Portrait tablets and up */
@media screen and (min-width: 768px) {
    .jumbotron {
        margin-top: 20px;
    }
    .body-content {
        padding: 0;
    }
}

/* Bootstrap's .table uses the browser's default table-layout: auto, which
   sizes each column from that table's own content - so a colgroup width hint
   alone doesn't guarantee the same column lines up the same way across
   several independent tables (e.g. per-employee ticket lists) when their
   content lengths differ. table-layout: fixed makes column widths purely a
   function of the colgroup - content just wraps instead of resizing anything. */
.table-fixed {
    table-layout: fixed;
}

/* Marks truncated comment text that opens a Bootstrap popover with the full
   text on click - a pointer cursor is the only thing this needs that a plain
   <a> would otherwise give for free. */
.popover-toggle {
    cursor: pointer;
}

/* Bootstrap 3 has no built-in styling hook for "show accordion state" the way
   Bootstrap 5's .accordion-button does, so this resets the plain <button> (used
   instead of an <a> - the Bootstrap 3 docs' own collapse example, and simpler
   than juggling an anchor with no href) to read as a clickable heading rather
   than a boxed button. Flexbox (not float/pull-right) positions the chevron -
   float is unreliable inside <button> elements across browsers, which is why
   an earlier pull-right attempt didn't visually move it. The rotation itself
   is keyed directly off aria-expanded, which bootstrap.js's show()/hide() set
   on this exact trigger unconditionally (confirmed in Scripts/bootstrap.js) -
   pure CSS, no custom JS/event-binding needed at all. */
.panel-title-toggle {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    padding: 0;
    border: none;
    background: none;
    text-align: left;
    font: inherit;
    color: inherit;
}

.panel-title-toggle .glyphicon-chevron-down {
    transition: transform 0.2s ease-in-out;
}

.panel-title-toggle[aria-expanded="true"] .glyphicon-chevron-down {
    transform: rotate(180deg);
}
```

| Rule | Decision | Reason |
|---|---|---|
| `body` `padding-top: 50px` | **adapt** | The Bootstrap 5 fixed navbar is about 56 px high; offset the content by the measured navbar height |
| `body` `padding-bottom: 20px`, `min-height: 100vh`, flex column | **adapt** | Apply to the Angular app shell (`d-flex flex-column min-vh-100`) instead of `body` |
| `body > form` flex | **obsolete** | Angular has no page-wide `form` wrapper |
| `.body-content` padding and flex | **adapt** | The shell's main content area: `container flex-grow-1`; keep 15 px side padding below 768 px |
| `.body-content footer` `margin-top: auto; padding-top: 20px` | **keep** | Sticky footer, applied to the shell's footer |
| `input, select, textarea { max-width: 280px }` | **keep** | Same field widths; scope it to the app's forms |
| `.jumbotron { margin-top: 20px }` at 768 px and up | **adapt** | Apply to the home page's hero panel |
| `.body-content { padding: 0 }` at 768 px and up | **adapt** | As `.body-content` above |
| `.table-fixed { table-layout: fixed }` | **keep** | Aligns columns across several tables (pages 9, 12) |
| `.popover-toggle { cursor: pointer }` | **obsolete** | The trigger becomes a `button` |
| `.panel-title-toggle` and its chevron rotation | **obsolete** | ng-bootstrap's accordion button draws and rotates its own chevron |

New custom classes: `.metrics-scroll` (`height: 330px; overflow-y: auto`) and `.metrics-pie` (`height: 330px`) for
page 10; a visually hidden utility already exists in 5.3 (`visually-hidden`) for the hidden table headers and
captions in `VIEW.md`.

## Layout shell

- **Navbar**: `navbar navbar-expand-md navbar-dark bg-dark fixed-top`, inside a `container`: brand (wrench icon and
  "Home"), toggler, collapsible content with the role menu on the left and the sign-in area on the right (`ms-auto`).
  The signed-in greeting is `navbar-text`.
- **Skip link**: a `visually-hidden-focusable` link "Skip to main content" before the navbar.
- **Main**: `main` landmark, `container` with the page content, offset below the fixed navbar.
- **Footer**: a horizontal rule, then `<footer><p>&copy; {year} - Master Antique Repair</p></footer>`, pinned to the
  bottom of the viewport on short pages.
- **Document**: `lang="en"`, `meta viewport` `width=device-width, initial-scale=1.0`, the legacy `favicon.ico`.
