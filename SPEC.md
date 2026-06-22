# jupiterweb.el Technical Specification

## 1. Purpose

`jupiterweb` is an Emacs Lisp package for querying, caching, viewing, inserting, and exporting curriculum and discipline syllabus data from USP JupiterWeb.

The package must support the Physics Teaching Degree curriculum by default, while allowing other USP courses through customizable variables.

Default curriculum URL:

```text
https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=43&codcur=43031&codhab=0&tipo=N
```

Default discipline URL pattern:

```text
https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=4300151&codcur=43031&codhab=0
```

The package must be called `jupiterweb`.

## 2. Important implementation constraint: port the existing Python scraper

The repository already has `scrape_jupiterweb.py`. The Emacs Lisp implementation must not treat the scraper as a greenfield project. The existing Python script is the reference implementation for:

- tolerant page decoding;
- CP1252 and ISO-8859-1 cleanup;
- invisible Unicode-space cleanup;
- HTML-to-text conversion;
- discipline-page parsing;
- section delimiter detection;
- instructor extraction;
- fallback records for provisional or missing disciplines;
- final recursive record cleanup before JSON output.

### 2.1. Python-to-Elisp porting map

| Python item | Elisp target | Requirement |
|---|---|---|
| `decodificar_pagina` | `jupiterweb--decode-response` | Preserve tolerant decoding: CP1252, ISO-8859-1, UTF-8 fallback. |
| `fetch_page` | `jupiterweb-http-get`, `jupiterweb-fetch-discipline-html` | Generalize for both curriculum and discipline endpoints. |
| `normalizar_unicode` | `jupiterweb--normalize-unicode` | Port CP1252 controls and invisible-space cleanup. |
| `converter_aspas_duplas` | `jupiterweb--convert-double-quotes` | Keep as optional cleanup for exported text. |
| `limpar_texto_campo` | `jupiterweb--clean-field-text` | Support preserving or flattening line breaks. |
| `clean_text` | `jupiterweb--html-to-plain-text` | Preserve structural breaks needed for section parsing. |
| `parse_disciplina` | `jupiterweb-parse-discipline` | Main discipline parser; port behavior incrementally. |
| `normalizar_unidade` | `jupiterweb--normalize-unit` | Normalize USP units such as IF, IME, FE, IQ. |
| `normalizar_chave` | `jupiterweb--normalize-key` | Convert Portuguese headings to ASCII keys. |
| `extrair_numero` | `jupiterweb--extract-number` | Extract integer fields. |
| `heading_pattern` | `jupiterweb--heading-regexp` | Match only isolated section headings. |
| `extrai_secao` | `jupiterweb--extract-section` | Extract a section up to the next delimiter heading. |
| `extrai_secoes` | `jupiterweb--extract-sections` | Extract all known sections. |
| `extrair_valor_label` | `jupiterweb--extract-label-value` | Extract short labels without capturing the next section. |
| `extrai_docentes` | `jupiterweb--extract-instructors` | Convert `12345 - Name` occurrences into structured records. |
| `limpar_registro` | `jupiterweb--clean-record` | Recursively clean strings in records. |
| `build_estrutura` | `jupiterweb--build-curriculum-record` | Adapt to data scraped from the web curriculum page. |
| `build_ementa_fallback` | `jupiterweb--build-syllabus-fallback` | Preserve fallback behavior for `XXX` or failed disciplines. |

### 2.2. Python code that must not be copied literally

The Python script currently uses local paths such as:

```text
/root/.hermes/hermes-agent/transfer
transfer/coc/estrutura-curricular.csv
transfer/coc-db/ementas-lic.json
transfer/coc-db/estrutura-curricular.json
```

The Emacs package must not hard-code those paths. Cache and export paths must be controlled by Emacs variables and interactive commands.

The package may later support CSV import, but the primary source of the discipline list must be the JupiterWeb curriculum page.

## 3. Package layout

Recommended files:

```text
jupiterweb.el
jupiterweb-vars.el
jupiterweb-http.el
jupiterweb-parse.el
jupiterweb-cache.el
jupiterweb-ui.el
jupiterweb-transient.el
jupiterweb-export.el
test/jupiterweb-test.el
test/fixtures/
README.md
SPEC.md
todo.org
DECISIONS.md
```

Responsibilities:

- `jupiterweb.el`: package entry point and public autoloads.
- `jupiterweb-vars.el`: customization group, variables, in-memory state.
- `jupiterweb-http.el`: HTTP retrieval, URL building, decoding, retries.
- `jupiterweb-parse.el`: curriculum parser and discipline parser.
- `jupiterweb-cache.el`: JSON cache read/write, cache invalidation, refresh commands.
- `jupiterweb-ui.el`: selection, insertion, Consult/Marginalia, view buffer.
- `jupiterweb-transient.el`: Transient menu.
- `jupiterweb-export.el`: JSON export.
- `test/jupiterweb-test.el`: ERT tests.
- `test/fixtures/`: offline HTML and expected JSON fixtures.
- `DECISIONS.md`: implementation decisions and deviations.

## 4. Dependencies

Required built-in libraries:

```elisp
(require 'url)
(require 'url-parse)
(require 'json)
(require 'dom)
(require 'subr-x)
(require 'seq)
(require 'cl-lib)
```

Optional libraries:

```elisp
(require 'consult nil t)
(require 'marginalia nil t)
(require 'transient nil t)
```

Fallback behavior:

- Without Consult: use `completing-read`.
- Without Marginalia: show plain candidates.
- Without Transient: public commands must still work.

## 5. Custom variables

Define:

```elisp
(defgroup jupiterweb nil
  "Query and insert USP JupiterWeb curriculum data."
  :group 'applications)
```

Required variables:

```elisp
(defcustom jupiterweb-codcg "43"
  "USP unit code used by JupiterWeb."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-codcur "43031"
  "USP course code used by JupiterWeb."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-codhab "0"
  "USP habilitation code used by JupiterWeb."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-tipo "N"
  "JupiterWeb curriculum type."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-cache-directory
  (expand-file-name "jupiterweb/" user-emacs-directory)
  "Directory where jupiterweb stores JSON cache files."
  :type 'directory
  :group 'jupiterweb)

(defcustom jupiterweb-cache-fetch-policy 'lazy
  "When to fetch missing syllabus data: lazy, eager, or manual."
  :type '(choice
          (const :tag "Fetch syllabus on demand" lazy)
          (const :tag "Fetch all syllabi when refreshing curriculum" eager)
          (const :tag "Never fetch automatically" manual))
  :group 'jupiterweb)

(defcustom jupiterweb-http-timeout 40
  "Timeout in seconds for JupiterWeb HTTP requests."
  :type 'integer
  :group 'jupiterweb)

(defcustom jupiterweb-retries 3
  "Number of HTTP retries for JupiterWeb requests."
  :type 'integer
  :group 'jupiterweb)

(defcustom jupiterweb-request-delay 0.5
  "Delay in seconds between batch requests."
  :type 'number
  :group 'jupiterweb)

(defcustom jupiterweb-user-agent
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 jupiterweb.el"
  "User-Agent string used for JupiterWeb requests."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-codhab-fallbacks '("0" "4")
  "Habilitation codes to try when fetching a discipline syllabus."
  :type '(repeat string)
  :group 'jupiterweb)

(defcustom jupiterweb-view-side 'right
  "Side used to display syllabus buffers."
  :type '(choice (const left) (const right) (const top) (const bottom))
  :group 'jupiterweb)

(defcustom jupiterweb-view-window-width 0.42
  "Relative width of the syllabus side window."
  :type 'number
  :group 'jupiterweb)
```

When `jupiterweb-codcg`, `jupiterweb-codcur`, `jupiterweb-codhab`, or `jupiterweb-tipo` changes, the package must clear in-memory caches and reload the matching disk cache if available.

Public helper:

```elisp
(defun jupiterweb-set-course (&key codcg codcur codhab tipo)
  "Set the current JupiterWeb course parameters and reload matching cache.")
```

## 6. Data model

### 6.1. Curriculum object

```elisp
(:package "jupiterweb"
 :kind "curriculum"
 :schema-version 1
 :codcg "43"
 :codcur "43031"
 :codhab "0"
 :tipo "N"
 :source-url "https://..."
 :fetched-at "2026-06-21T15:30:00-03:00"
 :disciplines (...))
```

### 6.2. Minimal discipline object

```elisp
(:sgldis "4300151"
 :name "Fundamentos de Mecânica"
 :name-normalized "fundamentos de mecanica"
 :unit "IF"
 :period "1"
 :term-day 1
 :term-night 1
 :block "mandatory"
 :nature "mandatory"
 :credits-lecture 4
 :credits-work 0
 :workload-total 60
 :workload-class 60
 :workload-work 0
 :workload-extension nil
 :workload-internship nil
 :source-url "https://...")
```

### 6.3. Full syllabus object

```elisp
(:sgldis "4300151"
 :name "Fundamentos de Mecânica"
 :name-en "Introduction to Mechanics"
 :unit "IF"
 :group nil
 :credits-lecture 4
 :credits-work 0
 :workload-total 60
 :workload-pcc nil
 :workload-internship nil
 :workload-extension nil
 :extra nil
 :type "Semestral"
 :activation "..."
 :deactivation nil
 :syllabus "..."
 :objectives "..."
 :summary-program "..."
 :program "..."
 :teaching-method "..."
 :assessment-method "..."
 :recovery-rule "..."
 :bibliography "..."
 :basic-bibliography "..."
 :complementary-bibliography "..."
 :sustainable-development-goals "..."
 :instructors "..."
 :instructors-list ((:code "12345" :name "Instructor Name"))
 :source-url "https://..."
 :fetched-at "2026-06-21T15:30:00-03:00"
 :raw-text "...")
```

### 6.4. JSON field names

Exported JSON must use snake_case keys:

```text
sgldis
name
name_en
unit
group
credits_lecture
credits_work
workload_total
workload_pcc
workload_internship
workload_extension
summary_program
teaching_method
assessment_method
recovery_rule
basic_bibliography
complementary_bibliography
sustainable_development_goals
instructors
instructors_list
source_url
fetched_at
raw_text
```

## 7. URL builders and HTTP

Required functions:

```elisp
(defun jupiterweb--grade-url (&optional codcg codcur codhab tipo)
  "Return the JupiterWeb curriculum URL for the selected course.")

(defun jupiterweb--discipline-url (sgldis &optional codcur codhab)
  "Return the JupiterWeb discipline URL for SGLDIS.")

(defun jupiterweb-http-get (url)
  "Return decoded HTML from URL as a string.")

(defun jupiterweb-fetch-curriculum-html (&optional codcg codcur codhab tipo)
  "Fetch the current curriculum HTML.")

(defun jupiterweb-fetch-discipline-html (sgldis &optional codcur codhab)
  "Fetch a discipline syllabus HTML page.")
```

HTTP requirements:

1. Use `url-retrieve-synchronously`.
2. Respect `jupiterweb-http-timeout`.
3. Send `jupiterweb-user-agent`.
4. Strip HTTP headers.
5. Decode robustly.
6. Retry using `jupiterweb-retries` where appropriate.
7. Return clear errors for network failures.

## 8. Decoding and normalization

Port Python decoding and cleanup behavior.

Required functions:

```elisp
(defun jupiterweb--decode-response (bytes-or-buffer)
  "Decode a JupiterWeb HTTP response robustly.")

(defun jupiterweb--fix-cp1252-controls (text)
  "Fix common CP1252 control characters.")

(defun jupiterweb--normalize-unicode (text)
  "Remove invisible spaces and normalize Unicode.")

(defun jupiterweb--convert-double-quotes (text)
  "Convert safe internal straight quotes to typographic quotes.")

(defun jupiterweb--clean-field-text (text &optional preserve-breaks)
  "Clean a parsed field.")

(defun jupiterweb--html-to-plain-text (html)
  "Convert HTML to text while preserving section heading line breaks.")
```

`jupiterweb--html-to-plain-text` must:

1. Remove `<script>` and `<style>`.
2. Convert `<br>` to newlines.
3. Convert block closing tags to newlines.
4. Convert `<li>` to bullet-like lines.
5. Convert table cells to spaces.
6. Remove remaining tags.
7. HTML-unescape twice.
8. Normalize Unicode.
9. Normalize whitespace without destroying section headings.

## 9. Curriculum parser

Required function:

```elisp
(defun jupiterweb-parse-curriculum (html)
  "Extract discipline records from a JupiterWeb curriculum HTML page.")
```

Requirements:

1. Find all links to `obterDisciplina`.
2. Extract `sgldis` from each link.
3. Extract discipline names from link text or the surrounding row.
4. Preserve page order.
5. Remove duplicate `sgldis`, keeping first occurrence.
6. Extract semester/period and block/nature when possible.
7. Do not depend on fragile CSS classes.
8. Prefer DOM parsing if available.
9. Provide regex fallback.
10. If no disciplines are found, do not write a successful cache.

Patterns to support:

```text
obterDisciplina?sgldis=4300151&codcur=43031&codhab=0
obterDisciplina?codcur=43031&codhab=0&sgldis=4300151
4300151 Fundamentos de Mecânica
4300151 - Fundamentos de Mecânica
Fundamentos de Mecânica
```

## 10. Discipline parser

Required function:

```elisp
(defun jupiterweb-parse-discipline (html &optional sgldis source-url)
  "Extract syllabus data from a JupiterWeb discipline HTML page.")
```

This must port/adapt Python `parse_disciplina`.

Required section labels:

```text
Ementa
Objetivos
Conteúdo Programático
Programa
Método de Ensino
Critério de Avaliação
Norma de Recuperação
Bibliografia Básica
Bibliografia Complementar
Bibliografia
Objetivos de Desenvolvimento Sustentável (ONU)
Docente(s) Responsável(eis)
```

Required delimiter labels:

```text
Instrumentos e Critérios de Avaliação
Método de Avaliação
Créditos Aula
Créditos Trabalho
Carga Horária Total
Carga Horária de Extensão
Tipo
Ativação
Desativação
Clique
Créditos
Fale conosco
```

The parser must extract:

- `sgldis`;
- Portuguese discipline name;
- English discipline name, when present;
- unit and group;
- lecture credits;
- work credits;
- total workload;
- PCC workload;
- internship workload;
- extension workload;
- type;
- activation;
- deactivation;
- syllabus;
- objectives;
- summary program/content program;
- program;
- teaching method;
- assessment method;
- recovery rule;
- bibliography;
- basic bibliography;
- complementary bibliography;
- sustainable development goals;
- instructors as raw text;
- instructors as structured list;
- source URL;
- fetch timestamp;
- raw normalized text.

Section extraction rule:

A section heading must be an isolated heading line. Do not match heading words inside paragraphs.

Program fallback:

If `summary-program` is missing, use `program` as fallback, preserving the Python behavior.

Instructor extraction:

```text
12345 - Instructor Name 67890 - Another Instructor
```

must become:

```elisp
((:code "12345" :name "Instructor Name")
 (:code "67890" :name "Another Instructor"))
```

## 11. Cache

Cache directory:

```elisp
jupiterweb-cache-directory
```

Curriculum cache filename:

```text
grade-codcg-43-codcur-43031-codhab-0-tipo-N.json
```

Discipline cache filename:

```text
disciplina-4300151-codcur-43031-codhab-0.json
```

Required functions:

```elisp
(defun jupiterweb-cache-read-curriculum ())
(defun jupiterweb-cache-write-curriculum (curriculum))
(defun jupiterweb-cache-read-discipline (sgldis))
(defun jupiterweb-cache-write-discipline (sgldis data))
(defun jupiterweb-cache-curriculum-exists-p ())
(defun jupiterweb-cache-discipline-exists-p (sgldis))
(defun jupiterweb-cache-clear-memory ())
(defun jupiterweb-cache-clear-disk (&optional course-only))
```

Every cache file must include:

```text
package
kind
schema_version
codcg
codcur
codhab
tipo
source_url
fetched_at
```

Fetch policy:

- `lazy`: fetch curriculum when needed; fetch syllabus only when selected/viewed/inserted.
- `eager`: refreshing curriculum also refreshes all syllabi.
- `manual`: never fetch missing syllabi automatically.

Default: `lazy`.

## 12. Public commands

Required interactive commands:

```elisp
jupiterweb-refresh-curriculum-cache
jupiterweb-refresh-grade-cache ; alias
jupiterweb-refresh-discipline-cache
jupiterweb-refresh-all-discipline-caches
jupiterweb-select-discipline
jupiterweb-insert-name-code
jupiterweb-insert-code-name
jupiterweb-insert-discipline-section
jupiterweb-view-discipline
jupiterweb-export-cache-json
jupiterweb-set-course
jupiterweb-dispatch
```

### 12.1. Insert formats

The package must insert:

```text
Fundamentos de Mecânica (4300151)
```

and:

```text
4300151 - Fundamentos de Mecânica
```

### 12.2. Section insertion

The command `jupiterweb-insert-discipline-section` must:

1. Ask for a discipline.
2. Load or fetch the syllabus according to policy.
3. Ask for a section.
4. Insert editable plain text into the current buffer.

Sections should include:

- Objectives
- Summary Program
- Program
- Teaching Method
- Assessment
- Recovery Rule
- Bibliography
- Basic Bibliography
- Complementary Bibliography
- Instructors

## 13. Consult and Marginalia

When Consult is available, `jupiterweb-select-discipline` should use Consult.

When Consult is unavailable, use `completing-read`.

Candidate category:

```elisp
'jupiterweb-discipline
```

Search must work by:

- discipline name;
- discipline code;
- `Name (Code)` format;
- `Code - Name` format;
- accent-insensitive key when possible.

Marginalia annotations should show:

```text
4300151  IF  4A+0T  60h  cached
```

or as many fields as are available.

## 14. View buffer

Define:

```elisp
(define-derived-mode jupiterweb-view-mode special-mode "JupiterWeb"
  "Read-only mode for viewing JupiterWeb syllabus data.")
```

Buffer name:

```text
*JupiterWeb: 4300151 - Fundamentos de Mecânica*
```

Layout example:

```text
4300151 - Fundamentos de Mecânica
Introduction to Mechanics

Unit:                IF
Credits Lecture:     4
Credits Work:        0
Total Workload:      60 h
Type:                Semestral
Activation:          ...

────────────────────────────────────────
Objectives
────────────────────────────────────────

...

────────────────────────────────────────
Summary Program
────────────────────────────────────────

...

────────────────────────────────────────
Program
────────────────────────────────────────

...

────────────────────────────────────────
Assessment
────────────────────────────────────────

...

────────────────────────────────────────
Bibliography
────────────────────────────────────────

...
```

Keybindings:

| Key | Action |
|---|---|
| `q` | Quit window |
| `g` | Refresh current syllabus |
| `i` | Insert `Name (Code)` into origin buffer, when available |
| `I` | Insert `Code - Name` into origin buffer, when available |

## 15. Transient menu

Main command:

```elisp
jupiterweb-dispatch
```

Menu layout:

```text
JupiterWeb

Insert
 n  Insert Name (Code)
 i  Insert Code - Name
 s  Insert selected syllabus section
 o  Insert objectives
 r  Insert summary program
 p  Insert program
 a  Insert assessment
 b  Insert bibliography

View
 v  View syllabus in side buffer

Cache
 g  Refresh curriculum cache
 d  Refresh one discipline syllabus
 A  Refresh all discipline syllabi
 m  Clear memory cache
 C  Clear disk cache

Export
 j  Export cache to JSON

Course
 u  Set course parameters
```

Every menu item must call a public command. No feature may exist only inside the Transient menu.

## 16. JSON export

Command:

```elisp
(defun jupiterweb-export-cache-json (file &optional fetch-missing)
  "Export current curriculum and cached syllabi to FILE as JSON.")
```

Behavior:

- Without prefix: export only cached data.
- With `C-u`: fetch missing syllabi before exporting.

Output shape:

```json
{
  "package": "jupiterweb",
  "schema_version": 1,
  "exported_at": "2026-06-21T15:30:00-03:00",
  "course": {
    "codcg": "43",
    "codcur": "43031",
    "codhab": "0",
    "tipo": "N",
    "curriculum_source_url": "https://..."
  },
  "disciplines": [
    {
      "sgldis": "4300151",
      "name": "Fundamentos de Mecânica",
      "unit": "IF",
      "block": "mandatory",
      "syllabus_status": "cached",
      "syllabus": {
        "name_en": "Introduction to Mechanics",
        "credits_lecture": 4,
        "credits_work": 0,
        "workload_total": 60,
        "type": "Semestral",
        "activation": "...",
        "objectives": "...",
        "summary_program": "...",
        "program": "...",
        "assessment_method": "...",
        "bibliography": "..."
      }
    }
  ],
  "failures": []
}
```

If a syllabus is missing and `fetch-missing` is nil:

```json
{
  "sgldis": "4300151",
  "name": "Fundamentos de Mecânica",
  "syllabus_status": "missing",
  "syllabus": null
}
```

## 17. Provisional and failed discipline behavior

Discipline codes ending in `XXX` are provisional and must not trigger JupiterWeb network requests.

For provisional or failed disciplines, create fallback records compatible with export and UI display.

Fallback records must include:

- `sgldis`;
- name if known;
- workload/credits if known;
- `syllabus_status`;
- `observation` explaining why no syllabus exists.

## 18. Error handling

Rules:

1. Use `user-error` for invalid interactive use.
2. Use `display-warning` for recoverable parser/cache problems.
3. Use `condition-case` around network and parser operations.
4. Batch refresh must continue after individual failures.
5. Do not write a successful cache if parsing returns no disciplines.

Example messages:

```text
JupiterWeb: could not fetch curriculum for codcur=43031.
JupiterWeb: no discipline links were found in the curriculum HTML.
JupiterWeb: discipline 4300151 is not cached; fetching now...
JupiterWeb: parser could not find 'Créditos Aula' or 'Disciplina:' in the HTML.
JupiterWeb: cache file is corrupted; refresh the cache.
```

## 19. Tests

Use ERT.

Tests must run offline by default.

Required fixtures:

```text
test/fixtures/grade-43031.html
test/fixtures/disciplina-4300151.html
test/fixtures/disciplina-4300151.parsed.json
```

Required tests:

```text
jupiterweb-test-grade-url
jupiterweb-test-discipline-url
jupiterweb-test-current-course-key
jupiterweb-test-decode-response-cp1252
jupiterweb-test-cp1252-control-mapping
jupiterweb-test-invisible-space-normalization
jupiterweb-test-clean-field-text
jupiterweb-test-html-to-plain-text
jupiterweb-test-normalize-key
jupiterweb-test-to-integer
jupiterweb-test-heading-regexp
jupiterweb-test-extract-section
jupiterweb-test-extract-label-value
jupiterweb-test-extract-instructors
jupiterweb-test-parse-curriculum-links
jupiterweb-test-parse-curriculum-names
jupiterweb-test-parse-curriculum-dedup-order
jupiterweb-test-parse-discipline-identity
jupiterweb-test-parse-discipline-numeric-fields
jupiterweb-test-parse-discipline-sections
jupiterweb-test-parse-discipline-python-parity
jupiterweb-test-cache-filenames
jupiterweb-test-cache-curriculum-roundtrip
jupiterweb-test-cache-discipline-roundtrip
jupiterweb-test-format-name-code
jupiterweb-test-format-code-name
jupiterweb-test-export-json
jupiterweb-test-provisional-xxx-code
```

Optional network tests must be disabled by default:

```elisp
(defcustom jupiterweb-test-enable-network nil
  "When non-nil, allow tests to access JupiterWeb."
  :type 'boolean
  :group 'jupiterweb)
```

## 20. Development workflow

Development must be driven by `todo.org`.

Agent rules:

1. Read `SPEC.md`, `todo.org`, `DECISIONS.md`, and `scrape_jupiterweb.py` before editing parser-related code.
2. Work on only one `NEXT` task at a time.
3. Do not edit `SPEC.md` unless explicitly instructed.
4. Prefer porting existing Python logic over inventing new parser logic.
5. Add tests before or together with behavior changes.
6. Mark tasks as `REVIEW` if implemented but not verified.
7. Mark tasks as `DONE` only after acceptance criteria are met.
8. Record deviations or important implementation choices in `DECISIONS.md`.

## 21. Acceptance criteria

The package is acceptable when:

1. `M-x jupiterweb-refresh-curriculum-cache` fetches and caches the curriculum.
2. The curriculum parser extracts disciplines with `sgldis` and names.
3. `M-x jupiterweb-select-discipline` searches by name and code.
4. Searching for `4300151` finds the correct discipline.
5. Searching for part of `Fundamentos de Mecânica` finds the discipline.
6. `M-x jupiterweb-insert-name-code` inserts `Fundamentos de Mecânica (4300151)`.
7. `M-x jupiterweb-insert-code-name` inserts `4300151 - Fundamentos de Mecânica`.
8. `M-x jupiterweb-view-discipline` opens a read-only side buffer.
9. The side buffer shows metadata and syllabus sections.
10. `M-x jupiterweb-insert-discipline-section` inserts selected syllabus sections.
11. Cache is reused on repeated queries.
12. The default `lazy` policy does not fetch all syllabi automatically.
13. `M-x jupiterweb-refresh-all-discipline-caches` fetches all non-provisional syllabi.
14. Changing `jupiterweb-codcur` invalidates in-memory curriculum data.
15. `M-x jupiterweb-export-cache-json` creates valid JSON.
16. The package works without Consult.
17. The package uses Consult when available.
18. Marginalia annotations appear when Marginalia is available.
19. The Transient dispatcher works when Transient is available.
20. Unit tests run without internet.
21. Discipline parsing behavior is demonstrably ported from `scrape_jupiterweb.py`.
22. Provisional `XXX` discipline codes do not trigger network fetches.
23. Network and parser errors are understandable and recoverable.
