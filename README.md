# jupiterweb

Aplicação em emacs lisp para ter acesso aos dados das disciplinas no jupiterweb da usp.

Emacs Lisp package for querying, caching, viewing, inserting, and exporting
USP JupiterWeb curriculum and syllabus data.

## Installation

```elisp
(use-package jupiterweb
  :load-path "path/to/jupiterweb/"
  :custom
  (jupiterweb-codcg "43")
  (jupiterweb-codcur "43031")
  (jupiterweb-codhab "0")
  (jupiterweb-tipo "N"))
```

## Usage

### Basic commands

| Command | Description |
|---------|-------------|
| `M-x jupiterweb-refresh-curriculum-cache` | Fetch and cache curriculum data |
| `M-x jupiterweb-select-discipline` | Select a discipline by name or code |
| `M-x jupiterweb-insert-name-code` | Insert "Name (Code)" |
| `M-x jupiterweb-insert-code-name` | Insert "Code - Name" |
| `M-x jupiterweb-view-discipline` | View syllabus in side buffer |
| `M-x jupiterweb-insert-discipline-section` | Insert a syllabus section |
| `M-x jupiterweb-export-cache-json` | Export cached data to JSON |
| `M-x jupiterweb-set-course` | Set course parameters |
| `M-x jupiterweb-dispatch` | Transient menu (requires transient package) |

### Cache behavior

- **lazy** (default): Fetch syllabus on demand when selected/viewed/inserted.
- **eager**: Refresh all syllabi when refreshing curriculum.
- **manual**: Never fetch missing syllabi automatically.

### Python porting note

Parser logic was ported from `scrape_jupiterweb.py`. See `DECISIONS.md` for the
full Python-to-Elisp porting map.

## Testing

```bash
emacs --batch --eval "
  (let ((load-path (cons \".\" (cons \"test\" load-path))))
    (require 'jupiterweb-test)
    (ert-run-tests-batch-and-exit))"
```
