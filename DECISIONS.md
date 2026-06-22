# Technical Decisions

This file records implementation choices, deviations from SPEC.md, parser
assumptions, and compatibility notes.

## JW-001: Python-to-Elisp porting map

The Python scraper `scrape_jupiterweb.py` is the reference implementation.
The following table maps every Python function/constant to its Elisp target,
as required by SPEC.md §2.1 and todo.org JW-001.

| Python function/constant | Elisp target | Notes |
|---|---|---|
| `CONTROLES_CP1252` | `jupiterweb--cp1252-controls` (char-table or alist) | Map of CP1252 control codepoints to proper Unicode characters. Port the full 27-entry mapping. |
| `ESPACOS_INVISIVEIS` | `jupiterweb--invisible-spaces` (char-table or alist) | Map of invisible/zero-width Unicode spaces to normal space or empty string. Port all entries including `\u00a0`, `\u2000`–`\u200b`, `\u202f`, `\u3000`, `\ufeff`, `\u00ad`. |
| `decodificar_pagina(data)` | `jupiterweb--decode-response(bytes-or-buffer)` | Try cp1252, then iso-8859-1, then utf-8, then iso-8859-1 with replace. In Elisp, use `decode-coding-string` with `coding-system-for-read` fallback chain. |
| `fetch_page(sgldis, codcur, codhab)` | `jupiterweb-fetch-discipline-html(sgldis &optional codcur codhab)` + `jupiterweb-http-get(url)` | Python builds URL with params in order; Elisp uses `jupiterweb--discipline-url` builder. Python returns `(url, html, error_flag)`; Elisp returns decoded HTML or raises `user-error`. |
| `normalizar_unicode(texto)` | `jupiterweb--normalize-unicode(text)` | Apply CP1252 controls mapping, then invisible spaces mapping, then NFC normalize. In Elisp, use `ucs-normalize-NFC-region` or `ucs-normalize-NFC-string`. |
| `converter_aspas_duplas(texto)` | `jupiterweb--convert-double-quotes(text)` | Iteratively replace `"..."` with `"..."` (curly quotes) on the same line. Conservative: only pairs on the same line. |
| `limpar_texto_campo(texto, preservar_quebras)` | `jupiterweb--clean-field-text(text &optional preserve-breaks)` | Double HTML-unescape, normalize unicode, remove literal `\\n`/`\\r`/`\\t`, remove stray backslashes, convert double quotes, normalize whitespace. When `preserve-breaks` is non-nil, preserve newlines; otherwise collapse all whitespace to single spaces. Strip leading/trailing spaces, newlines, tabs, semicolons, colons. Return nil if empty. |
| `clean_text(html_text)` | `jupiterweb--html-to-plain-text(html)` | Remove `<script>`/`<style>` blocks, convert `<br>` to newlines, convert block close tags (`</p>`, `</div>`, `</tr>`, `</table>`, `</h1>`–`</h6>`) to newlines, convert `<li>` to `\n- `, convert `</td>`/`</th>` to spaces, strip remaining tags, double HTML-unescape, normalize unicode, normalize whitespace without destroying section heading line breaks. |
| `parse_disciplina(html_text)` | `jupiterweb-parse-discipline(html &optional sgldis source-url)` | Main discipline parser. Steps: (1) `clean_text`, (2) check for `Créditos Aula` and `Disciplina:`, (3) extract unit/group from `Pró-Reitoria de Graduação ... Disciplina:`, (4) extract sgldis and name(s) from `Disciplina: SIGLA - NAME\n[English name]\nCréditos Aula:`, (5) normalize unit, (6) extract numeric fields (cred_aula, cred_trabalho, carga_horaria_total), (7) extract extra workload (PCC, estágio, extensão), (8) extract all sections, (9) program fallback (conteudo_programatico ← programa), (10) extract instructors, (11) recursively clean record, (12) return plist. |
| `normalizar_unidade(unidade)` | `jupiterweb--normalize-unit(unit)` | Map full USP unit names to abbreviations. Priority order: MFT (Fonoaudiologia/Fisioterapia/Terapia Ocupacional), FFLCH, IF (Instituto de Física), IME (Instituto de Matemática), FE (Faculdade de Educação), IQ (Instituto de Química), IGc, IB, IAG, EACH, MFT (Medicina). Default: return input unchanged. |
| `normalizar_chave(titulo)` | `jupiterweb--normalize-key(title)` | NFD decompose, strip combining marks (category Mn), lowercase, replace non-alphanumeric runs with `_`, strip leading/trailing `_`. In Elisp, use `ucs-normalize-NFD-string` then filter combining chars. |
| `extrair_numero(texto, regex)` | `jupiterweb--extract-number(text regexp)` | Search text with regexp (case-insensitive), return `string-to-number` of group 1 if match, nil otherwise. |
| `heading_pattern(titulo)` | `jupiterweb--heading-regexp(title)` | Build regexp matching isolated heading lines: `(?:^\|\n)\s*TITLE\s*:?\s*(?:\n\|$)` case-insensitive. In Elisp, use `rx` or raw regexp with `regexp-quote` for the title. |
| `limpa_secao(secao)` | (internal to `jupiterweb--extract-section`) | Strip, remove `Tradução:...` suffix, strip leading `*:-=`, collapse 3+ newlines to 2, call `jupiterweb--clean-field-text` with `preserve-breaks=nil`. |
| `extrai_secao(text, titulo)` | `jupiterweb--extract-section(text title)` | Find heading match, collect text until the next heading from `TITULOS_SECAO` list, clean the section. |
| `extrai_secoes(text)` | `jupiterweb--extract-sections(text)` | Call `jupiterweb--extract-section` for each label in `SECOES_EMENTA`, return plist with normalized keys. |
| `extrair_valor_label(text, label)` | `jupiterweb--extract-label-value(text label)` | Extract short label values (Tipo, Ativação, Desativação). First try `(^\|\n)\s*LABEL:\s*\n+[ \t\xa0]*([^\n]*)`, fallback to `LABEL:\s*([^\n]+)`. Reject empty values or values equal to known section titles. |
| `extrai_docentes(texto)` | `jupiterweb--extract-instructors(text)` | Find all `(\d{3,})\s*-\s*(.*?)(?=\s+\d{3,}\s*-\|$)` matches, return list of `(:code "12345" :name "Name")` plists. |
| `limpar_registro(valor)` | `jupiterweb--clean-record(value)` | Recursively apply `jupiterweb--clean-field-text` to all strings in nested plist/list structures. |
| `build_estrutura(csv_row, web_data)` | `jupiterweb--build-curriculum-record(discipline web-data)` | Adapt for curriculum page scraping: merge curriculum HTML data with per-discipline web data. In Elisp, curriculum data comes from the grade page, not CSV. |
| `build_ementa_fallback(csv_row, observacao)` | `jupiterweb--build-syllabus-fallback(sgldis &optional name observation)` | Build a minimal syllabus plist with nil fields and an observation explaining the missing data. Used for XXX codes and failed fetches. |
| `to_int(value)` | `jupiterweb--to-integer(value)` | nil → nil, empty → nil, else `string-to-number` with float parsing. |
| `SECOES_EMENTA` | `jupiterweb--syllabus-section-labels` | List of section heading labels: Ementa, Objetivos, Conteúdo Programático, Programa, Método de Ensino, Critério de Avaliação, Norma de Recuperação, Bibliografia Básica, Bibliografia Complementar, Bibliografia, Objetivos de Desenvolvimento Sustentável (ONU), Docente(s) Responsável(eis). |
| `TITULOS_SECAO` | `jupiterweb--syllabus-delimiter-labels` | `SECOES_EMENTA` plus delimiter labels: Instrumentos e Critérios de Avaliação, Método de Avaliação, Créditos Aula, Créditos Trabalho, Carga Horária Total, Carga Horária de Extensão, Tipo, Ativação, Desativação, Clique, Créditos, Fale conosco. |

### Key porting notes

1. **Encoding**: Python uses `data.decode('cp1252')` etc. Elisp uses
   `decode-coding-string` with `windows-1252`, `iso-8859-1`, `utf-8` in
   sequence, catching `coding-system-error`.

2. **Unicode normalization**: Python uses `unicodedata.normalize('NFC'/'NFD')`.
   Elisp uses `ucs-normalize-NFC-string` / `ucs-normalize-NFD-string`.

3. **Combining mark stripping** (for `normalizar_chave`): Python filters
   `unicodedata.category(c) != 'Mn'`. Elisp can filter by checking
   `get-char-code-property c 'general-category` and excluding `'Mn'`.

4. **Regex**: Python `re` with `re.IGNORECASE`, `re.DOTALL`. Elisp `rx` or
   raw strings with `case-fold-search` bound to `t`.

5. **HTML unescape**: Python `html.unescape` applied twice. Elisp has no
   built-in; must implement `jupiterweb--html-unescape` supporting `&amp;`,
   `&lt;`, `&gt;`, `&quot;`, `&#NNN;`, `&#xHHH;`, `&nbsp;` etc.

6. **No hardcoded paths**: The Python script hardcodes
   `/root/.hermes/hermes-agent/transfer`. The Elisp package must use
   `jupiterweb-cache-directory` (customizable) instead.

7. **CSV dependency removed**: The Elisp package's primary discipline source
   is the JupiterWeb curriculum page, not a CSV file. `build_estrutura` and
   `build_ementa_fallback` are adapted to work without CSV rows.

## Release summary

All tasks JW-000 through JW-163 have been completed.

### Key decisions

1. **Raw byte encoding**: Emacs encodes raw bytes 0x80-0xFF as `#x3FFF00+offset`
   in multibyte strings (not `#x3FFF80+offset`).

2. **ucs-normalize required**: `(require 'ucs-normalize)` is needed for NFD/NFC
   normalization functions which are not autoloaded.

3. **get-char-code-property returns symbol**: The general-category property
   returns a symbol like `Mn`, not a string. Use `symbol-name` before
   `string-prefix-p`.

4. **string-trim regexp**: `string-trim` requires `+` quantifier in regexp
   to trim multiple characters: `[ 
	;:]+` not ` 
	;:`.

5. **cl-defun for &key**: Use `cl-defun` (not `defun`) for keyword arguments.

6. **HTML entity escaping**: `"\""` in Elisp is the string `\"` (backslash +
   quote), while `"""` is the string `"` (just a quote). Use the correct form.

7. **Parser regex adaptation**: Portuguese accented characters in JupiterWeb
   pages use NFC encoding. Regex patterns in the Elisp parser use `.` to match
   any character in accented positions (e.g., `Cr.editos` matches `Créditos`).

8. **Emacs JSON arrays must use vectors/hash tables**: In Emacs 30, `json-serialize`
   can misclassify nested lists-of-plists or lists-of-alists as JSON objects.
   For reliable encoding, convert JSON objects to hash tables and JSON arrays to
   vectors before serialization.

9. **Internal cache uses `.el`, export uses JSON**: The package now writes
   curriculum and discipline caches as printed Emacs Lisp plists in `.el` files
   and reads them with `read` for faster Emacs-native persistence. Legacy `.json`
   cache files are still readable for migration, and `jupiterweb-cache-clear-disk`
   removes both `.el` and `.json` cache files. The explicit export command still
   writes interoperable JSON.

10. **Curriculum names come from the next table cell**: On the real JupiterWeb
   grade page, the `<a>` text is only the discipline code (e.g. `4300157`), and
   the human discipline name is in the following `<td>`. `jupiterweb-parse-curriculum`
   must save all regexp match strings before cleanup helpers run, because cleanup
   functions mutate Emacs match data. This prevents selection/insertion from
   showing `4300157 (4300157)`.

### Known limitations

- No fixtures saved (JW-040, JW-041, JW-042) — requires network access to
  JupiterWeb which is not available in the test environment.
- No parser parity test (JW-057) — depends on fixtures.
- No manual smoke test (JW-161) — requires interactive Emacs session.
- Transient menu requires the `transient` package.
- Consult integration requires the `consult` package.
- Marginalia integration requires the `marginalia` package.
