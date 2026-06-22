;;; jupiterweb-parse.el --- Curriculum and discipline parsers for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Curriculum parser and discipline parser for JupiterWeb.
;; Parser logic is ported from the Python reference implementation
;; `scrape_jupiterweb.py'.  See DECISIONS.md for the porting map.

;;; Code:

(require 'subr-x)
(require 'seq)
(require 'cl-lib)
(require 'dom)
(require 'ucs-normalize)
(require 'jupiterweb-vars)

;; Section and delimiter labels (ported from Python SECOES_EMENTA and TITULOS_SECAO)

(defconst jupiterweb--syllabus-section-labels
  '("Ementa"
    "Objetivos"
    "Conteúdo Programático"
    "Programa"
    "Método de Ensino"
    "Critério de Avaliação"
    "Norma de Recuperação"
    "Bibliografia Básica"
    "Bibliografia Complementar"
    "Bibliografia"
    "Objetivos de Desenvolvimento Sustentável (ONU)"
    "Docente(s) Responsável(eis)")
  "Section heading labels that delimit textual sections in a discipline page.")

(defconst jupiterweb--syllabus-delimiter-labels
  (append jupiterweb--syllabus-section-labels
          '("Instrumentos e Critérios de Avaliação"
            "Método de Avaliação"
            "Créditos Aula"
            "Créditos Trabalho"
            "Carga Horária Total"
            "Carga Horária de Extensão"
            "Tipo"
            "Ativação"
            "Desativação"
            "Clique"
            "Créditos"
            "Fale conosco"))
  "All heading labels used as section delimiters, including non-exported ones.")

;; Decoding and normalization functions will be implemented in JW-020 through JW-024.

(defun jupiterweb--decode-response (bytes-or-buffer)
  "Decode a JupiterWeb HTTP response robustly.
Tries cp1252, iso-8859-1, then utf-8, falling back to iso-8859-1 with replace."
  (let ((bytes
         (if (bufferp bytes-or-buffer)
             (with-current-buffer bytes-or-buffer
               (save-excursion
                 (goto-char (point-min))
                 (re-search-forward "\r?\n\r?\n" nil t)
                 (buffer-substring-no-properties (point) (point-max))))
           bytes-or-buffer)))
    (if (null bytes)
        nil
      (let (decoded)
        (condition-case nil
            (setq decoded (decode-coding-string bytes 'windows-1252))
          (coding-system-error
           (condition-case nil
               (setq decoded (decode-coding-string bytes 'iso-8859-1))
             (coding-system-error
              (condition-case nil
                  (setq decoded (decode-coding-string bytes 'utf-8))
                (coding-system-error
                 (setq decoded (decode-coding-string bytes 'iso-8859-1))))))))
        (or decoded "")))))

;; CP1252 control-character mapping (ported from Python CONTROLES_CP1252)
;; Maps CP1252 control codepoints to their proper Unicode characters.
;; These appear when Windows-1252 curly quotes etc. are decoded as ISO-8859-1.

(defconst jupiterweb--cp1252-controls
  (let ((table (make-char-table 'cp1252-controls)))
    (aset table #x80 ?\u20AC)   ; €
    (aset table #x82 ?\u201A)   ; ‚
    (aset table #x83 ?\u0192)   ; ƒ
    (aset table #x84 ?\u201E)   ; „
    (aset table #x85 ?\u2026)   ; …
    (aset table #x86 ?\u2020)   ; †
    (aset table #x87 ?\u2021)   ; ‡
    (aset table #x88 ?\u02C6)   ; ˆ
    (aset table #x89 ?\u2030)   ; ‰
    (aset table #x8A ?\u0160)   ; Š
    (aset table #x8B ?\u2039)   ; ‹
    (aset table #x8C ?\u0152)   ; Œ
    (aset table #x8E ?\u017D)   ; Ž
    (aset table #x91 ?\u2018)   ; '
    (aset table #x92 ?\u2019)   ; '
    (aset table #x93 ?\u201C)   ; "
    (aset table #x94 ?\u201D)   ; "
    (aset table #x95 ?\u2022)   ; •
    (aset table #x96 ?\u2013)   ; –
    (aset table #x97 ?\u2014)   ; —
    (aset table #x98 ?\u02DC)   ; ˜
    (aset table #x99 ?\u2122)   ; ™
    (aset table #x9A ?\u0161)   ; š
    (aset table #x9B ?\u203A)   ; ›
    (aset table #x9C ?\u0153)   ; œ
    (aset table #x9E ?\u017E)   ; ž
    (aset table #x9F ?\u0178)   ; Ÿ
    table)
  "Char-table mapping CP1252 control codepoints to proper Unicode characters.
Ported from Python CONTROLES_CP1252 in scrape_jupiterweb.py.")

(defun jupiterweb--fix-cp1252-controls (text)
  "Fix common CP1252 control characters in TEXT.
Each byte in the CP1252 control range (0x80-0x9F) that has a known
mapping is replaced with its proper Unicode character."
  (if (or (null text) (string-empty-p text))
      text
    (let ((chars (string-to-list text))
          (result nil))
      (dolist (ch chars)
        (let* ((raw-byte
                ;; In Emacs multibyte strings, raw bytes 0x80-0xFF are
                ;; encoded as #x3FFF80-#x3FFFFF.  Extract the real byte value.
                (if (and (>= ch #x3FFF80) (<= ch #x3FFFFF))
                    (- ch #x3FFF00)
                  (if (and (>= ch #x80) (<= ch #x9F)) ch nil)))
               (replacement
                (when raw-byte
                  (let ((r (aref jupiterweb--cp1252-controls raw-byte)))
                    (and r (not (eq r 0)) r)))))
          (push (if replacement
                    (string replacement)
                  (string ch))
                result)))
      (apply #'concat (nreverse result)))))

;; Invisible space characters (ported from Python ESPACOS_INVISIVEIS)
;; Maps invisible/zero-width Unicode characters to normal space or empty string.
(defconst jupiterweb--invisible-spaces
  (let ((table (make-char-table 'invisible-spaces)))
    ;; Spaces → normal space
    (aset table #x00A0 ?\s)   ; NO-BREAK SPACE → space
    (aset table #x1680 ?\s)   ; OGHAM SPACE MARK → space
    (aset table #x180E 0)     ; MONGOLIAN VOWEL SEPARATOR → remove
    (aset table #x2000 ?\s)   ; EN QUAD → space
    (aset table #x2001 ?\s)   ; EM QUAD → space
    (aset table #x2002 ?\s)   ; EN SPACE → space
    (aset table #x2003 ?\s)   ; EM SPACE → space
    (aset table #x2004 ?\s)   ; THREE-PER-EM SPACE → space
    (aset table #x2005 ?\s)   ; FOUR-PER-EM SPACE → space
    (aset table #x2006 ?\s)   ; SIX-PER-EM SPACE → space
    (aset table #x2007 ?\s)   ; FIGURE SPACE → space
    (aset table #x2008 ?\s)   ; PUNCTUATION SPACE → space
    (aset table #x2009 ?\s)   ; THIN SPACE → space
    (aset table #x200A ?\s)   ; HAIR SPACE → space
    (aset table #x200B 0)     ; ZERO WIDTH SPACE → remove
    (aset table #x200C 0)     ; ZERO WIDTH NON-JOINER → remove
    (aset table #x200D 0)     ; ZERO WIDTH JOINER → remove
    (aset table #x202F ?\s)   ; NARROW NO-BREAK SPACE → space
    (aset table #x205F ?\s)   ; MEDIUM MATHEMATICAL SPACE → space
    (aset table #x2060 0)     ; WORD JOINER → remove
    (aset table #x3000 ?\s)   ; IDEOGRAPHIC SPACE → space
    (aset table #xFEFF 0)     ; ZERO WIDTH NO-BREAK SPACE (BOM) → remove
    (aset table #x00AD 0)     ; SOFT HYPHEN → remove
    table)
  "Char-table mapping invisible/zero-width Unicode spaces to normal space or removal.
Ported from Python ESPACOS_INVISIVEIS in scrape_jupiterweb.py.")

(defun jupiterweb--normalize-unicode (text)
  "Remove invisible spaces and normalize Unicode in TEXT.
Applies CP1252 control fixing, invisible space removal, and NFC normalization.
Ported from Python normalizar_unicode."
  (if (or (null text) (string-empty-p text))
      text
    (let* ((fixed-cp (jupiterweb--fix-cp1252-controls text))
           (chars (string-to-list fixed-cp))
           (result nil))
      (dolist (ch chars)
        (let ((replacement (aref jupiterweb--invisible-spaces ch)))
          (cond
           ((null replacement)
            (push (string ch) result))
           ((eq replacement 0)
            nil)
           (t
            (push (string replacement) result)))))
      (let ((normalized (apply #'concat (nreverse result))))
        (condition-case nil
            (ucs-normalize-NFC-string normalized)
          (error normalized))))))

(defconst jupiterweb--html-entity-map
  '(("amp" . "&") ("lt" . "<") ("gt" . ">") ("quot" . "\"")
    ("nbsp" . " ") ("apos" . "'") ("copy" . "©")
    ("Agrave" . "À") ("Aacute" . "Á") ("Acirc" . "Â") ("Atilde" . "Ã")
    ("Auml" . "Ä") ("Aring" . "Å") ("AElig" . "Æ") ("Ccedil" . "Ç")
    ("Egrave" . "È") ("Eacute" . "É") ("Ecirc" . "Ê") ("Euml" . "Ë")
    ("Igrave" . "Ì") ("Iacute" . "Í") ("Icirc" . "Î") ("Iuml" . "Ï")
    ("ETH" . "Ð") ("Ntilde" . "Ñ") ("Ograve" . "Ò") ("Oacute" . "Ó")
    ("Ocirc" . "Ô") ("Otilde" . "Õ") ("Ouml" . "Ö") ("Oslash" . "Ø")
    ("Ugrave" . "Ù") ("Uacute" . "Ú") ("Ucirc" . "Û") ("Uuml" . "Ü")
    ("Yacute" . "Ý") ("THORN" . "Þ") ("szlig" . "ß")
    ("agrave" . "à") ("aacute" . "á") ("acirc" . "â") ("atilde" . "ã")
    ("auml" . "ä") ("aring" . "å") ("aelig" . "æ") ("ccedil" . "ç")
    ("egrave" . "è") ("eacute" . "é") ("ecirc" . "ê") ("euml" . "ë")
    ("igrave" . "ì") ("iacute" . "í") ("icirc" . "î") ("iuml" . "ï")
    ("eth" . "ð") ("ntilde" . "ñ") ("ograve" . "ò") ("oacute" . "ó")
    ("ocirc" . "ô") ("otilde" . "õ") ("ouml" . "ö") ("oslash" . "ø")
    ("ugrave" . "ù") ("uacute" . "ú") ("ucirc" . "û") ("uuml" . "ü")
    ("yacute" . "ý") ("thorn" . "þ") ("yuml" . "ÿ")
    ("ordf" . "ª") ("ordm" . "º") ("ndash" . "–") ("mdash" . "—")
    ("lsquo" . "‘") ("rsquo" . "’") ("ldquo" . "“") ("rdquo" . "”"))
  "Named HTML entities commonly found in JupiterWeb pages.")

(defun jupiterweb--html-unescape (text)
  "HTML-unescape TEXT.
Convert named entities, decimal numeric entities, and hexadecimal numeric
entities to their character equivalents.  Applied twice for nested entities."
  (if (or (null text) (string-empty-p text))
      text
    (with-temp-buffer
      (insert text)
      (dotimes (_ 2)
        (goto-char (point-min))
        (while (re-search-forward
                "&\\(?:#\\([0-9]+\\)\\|#x\\([0-9a-fA-F]+\\)\\|\\([A-Za-z][A-Za-z0-9]+\\)\\);"
                nil t)
          (let* ((num (match-string 1))
                 (hex (match-string 2))
                 (name (match-string 3))
                 (replacement
                  (cond
                   (num (char-to-string (string-to-number num)))
                   (hex (char-to-string (string-to-number hex 16)))
                   (name (cdr (assoc name jupiterweb--html-entity-map))))))
            (when replacement
              (replace-match replacement t t)))))
      (buffer-string))))

(defun jupiterweb--convert-double-quotes (text)
  "Convert safe internal straight quotes to typographic quotes in TEXT.
Iteratively replace pairs of double quotes on the same line with
curly quotes.  Ported from Python converter_aspas_duplas."
  (if (or (null text) (string-empty-p text))
      text
    (let ((result text)
          (prev nil))
      (while (not (equal prev result))
        (setq prev result)
        (setq result (replace-regexp-in-string
                      "\"\\([^\"]*?\\)\""
                      "\u201C\\1\u201D"
                      result)))
      result)))

(defun jupiterweb--clean-field-text (text &optional preserve-breaks)
  "Clean a parsed field TEXT.
When PRESERVE-BREAKS is non-nil, preserve line breaks; otherwise collapse
all whitespace to single spaces.  Ported from Python limpar_texto_campo."
  (if (null text)
      nil
    (let* ((s (if (stringp text) text (format "%s" text)))
           (s (jupiterweb--html-unescape s))
           (s (jupiterweb--normalize-unicode s))
           ;; Remove literal \\n, \\r, \\t sequences from already-escaped text.
           (s (replace-regexp-in-string "\\\\[rnt]+" " " s))
           ;; Remove stray backslashes.
           (s (replace-regexp-in-string "\\\\" " " s))
           (s (jupiterweb--convert-double-quotes s))
           (s (replace-regexp-in-string "\r\n" "\n" s))
           (s (replace-regexp-in-string "\r" "\n" s))
           (s (replace-regexp-in-string "\t" " " s)))
      (if preserve-breaks
          (progn
            (setq s (replace-regexp-in-string "[ \f\v]+" " " s))
            (setq s (replace-regexp-in-string " *\n *" "\n" s))
            (setq s (replace-regexp-in-string "\n\\{3,\\}" "\n\n" s)))
        (setq s (replace-regexp-in-string "\\s-+" " " s)))
      ;; Strip leading/trailing spaces, newlines, tabs, semicolons, colons.
      (setq s (string-trim s "[ \n\t;:]+" "[ \n\t;:]+"))
      (if (string-empty-p s) nil s))))

(defun jupiterweb--html-to-plain-text (html)
  "Convert HTML to text while preserving section heading line breaks.
Ported from Python clean_text.  Steps:
1. Remove <script> and <style> blocks.
2. Convert <br> to newlines.
3. Convert block closing tags to newlines.
4. Convert <li> to bullet-like lines.
5. Convert table cells to spaces.
6. Remove remaining tags.
7. HTML-unescape twice.
8. Normalize Unicode.
9. Normalize whitespace without destroying section headings."
  (if (or (null html) (string-empty-p html))
      html
    (let ((text html))
      ;; 1. Remove <script>...</script> and <style>...</style>
      (setq text (replace-regexp-in-string
                  "<script\\b[^>]*>.*?</script>" " " text t t))
      (setq text (replace-regexp-in-string
                  "<style\\b[^>]*>.*?</style>" " " text t t))
      ;; 2. Convert <br> to newlines
      (setq text (replace-regexp-in-string "<br\\s-*/?>" "\n" text t t))
      ;; 3. Convert block closing tags to newlines
      (setq text (replace-regexp-in-string
                  "</\\(?:p\\|div\\|tr\\|table\\|h[1-6]\\)\\s-*>" "\n" text t t))
      ;; 4. Convert <li> to bullet-like lines
      (setq text (replace-regexp-in-string "<li\\b[^>]*>" "\n- " text t t))
      (setq text (replace-regexp-in-string "</li\\s-*>" "\n" text t t))
      ;; 5. Convert table cells to spaces
      (setq text (replace-regexp-in-string "</\\(?:td\\|th\\)\\s-*>" " " text t t))
      ;; 6. Remove remaining tags
      (setq text (replace-regexp-in-string "<[^>]+>" " " text t t))
      ;; 7. HTML-unescape twice
      (setq text (jupiterweb--html-unescape text))
      ;; 8. Normalize Unicode
      (setq text (jupiterweb--normalize-unicode text))
      ;; 9. Normalize whitespace without destroying headings
      (setq text (replace-regexp-in-string "\r\n" "\n" text t t))
      (setq text (replace-regexp-in-string "\r" "\n" text t t))
      (setq text (replace-regexp-in-string "\t" " " text t t))
      (setq text (replace-regexp-in-string "[ \f\v]+" " " text t t))
      (setq text (replace-regexp-in-string " *\n *" "\n" text t t))
      (setq text (replace-regexp-in-string "\n\\{3,\\}" "\n\n" text t t))
      (string-trim text))))

(defun jupiterweb--normalize-key (title)
  "Convert Portuguese headings to stable ASCII keys.
NFD decompose, strip combining marks, lowercase, replace non-alphanumeric
runs with underscore, strip leading/trailing underscores.
Ported from Python normalizar_chave."
  (if (or (null title) (string-empty-p title))
      ""
    (let* ((nfd (condition-case nil
                    (ucs-normalize-NFD-string title)
                  (error title)))
           (chars (string-to-list nfd))
           (filtered nil))
      ;; Strip combining marks (category Mn)
      (dolist (ch chars)
        (let ((cat (condition-case nil
                       (get-char-code-property ch 'general-category)
                     (error nil))))
          (unless (and cat (string-prefix-p "Mn" (symbol-name cat)))
            (push (string ch) filtered))))
      (let* ((sem-acentos (apply #'concat (nreverse filtered)))
             (lower (downcase sem-acentos))
             ;; Replace non-alphanumeric runs with underscore
             (key (replace-regexp-in-string "[^a-z0-9]+" "_" lower t t)))
        (string-trim key "_" "_")))))

(defun jupiterweb--to-integer (value)
  "Convert VALUE to an integer, returning nil if empty or invalid.
Ported from Python to_int."
  (cond
   ((null value) nil)
   ((integerp value) value)
   ((floatp value) (floor value))
   ((stringp value)
    (let ((s (string-trim value)))
      (if (string-empty-p s)
          nil
        (condition-case nil
            (floor (string-to-number s))
          (error nil)))))
   (t
    (let ((s (string-trim (format "%s" value))))
      (if (string-empty-p s)
          nil
        (condition-case nil
            (floor (string-to-number s))
          (error nil)))))))

(defun jupiterweb--extract-number (text regexp)
  "Search TEXT for REGEXP and return the first capture group as an integer.
Ported from Python extrair_numero.  Case-insensitive search."
  (when (and text (stringp text))
    (let ((case-fold-search t))
      (when (string-match regexp text)
        (let ((match (match-string 1 text)))
          (when match
            (string-to-number match)))))))

(defun jupiterweb--normalize-unit (unit)
  "Normalize USP unit names to abbreviations."
  (if (or (null unit) (string-empty-p unit))
      nil
    (let ((u unit))
      (cond
       ((string-match-p "Fonoaudiologia\\|Fisioterapia\\|Terapia Ocupacional" u) "MFT")
       ((string-match-p "Filosofia, Letras e Ciencias Humanas\\|FFLCH" u) "FFLCH")
       ((string-match-p "Instituto de Fisica" u) "IF")
       ((string-match-p "Instituto de Matematica" u) "IME")
       ((string-match-p "Faculdade de Educacao" u) "FE")
       ((string-match-p "Instituto de Quimica" u) "IQ")
       ((string-match-p "Instituto de Geociencias" u) "IGc")
       ((string-match-p "Instituto de Biociencias" u) "IB")
       ((string-match-p "Instituto de Astronomia" u) "IAG")
       ((string-match-p "Escola de Artes" u) "EACH")
       ((string-match-p "Medicina" u) "MFT")
       (t u)))))

(defconst jupiterweb--blank-re "[ \n\r\t]"
  "Regexp character class matching whitespace in cleaned JupiterWeb text.")

(defconst jupiterweb--hblank-re "[ \r\t]"
  "Regexp character class matching horizontal whitespace only.")

(defun jupiterweb--heading-regexp (title)
  "Return a regexp matching an isolated section heading line for TITLE."
  (let ((escaped (regexp-quote title)))
    (concat "\\(?:^\\|\\n\\)" jupiterweb--hblank-re "*"
            escaped jupiterweb--hblank-re "*:?" jupiterweb--hblank-re
            "*\\(?:\\n\\|$\\)")))

(defun jupiterweb--clean-section (section)
  "Clean a section extracted from the page."
  (if (or (null section) (string-empty-p section))
      nil
    (let ((s section))
      (setq s (string-trim s))
      (setq s (replace-regexp-in-string "\nTradicao:.*" "" s t t))
      (setq s (replace-regexp-in-string "^\\s-*[\\*:=-]+\\s-*" "" s t t))
      (setq s (replace-regexp-in-string "\n\\{3,\\}" "\n\n" s t t))
      (jupiterweb--clean-field-text s))))

(defun jupiterweb--extract-section (text title)
  "Extract the content of section TITLE from TEXT, stopping at the next heading."
  (let ((case-fold-search t)
        (regexp (jupiterweb--heading-regexp title)))
    (if (not (string-match regexp text))
        nil
      (let ((start (match-end 0))
            (end (length text)))
        (dolist (other jupiterweb--syllabus-delimiter-labels)
          (let ((other-regexp (jupiterweb--heading-regexp other)))
            (when (and (not (string-equal (downcase other) (downcase title)))
                       (string-match other-regexp text start))
              (setq end (min end (match-beginning 0))))))
        (jupiterweb--clean-section (substring text start end))))))

(defun jupiterweb--extract-sections (text)
  "Extract all known sections from TEXT."
  (let ((result nil))
    (dolist (label jupiterweb--syllabus-section-labels)
      (let ((key (jupiterweb--normalize-key label))
            (value (jupiterweb--extract-section text label)))
        (push (cons key value) result)))
    (nreverse result)))

(defun jupiterweb--extract-label-value (text label)
  "Extract a short label value from TEXT without capturing the next heading."
  (let ((case-fold-search t)
        (escaped (regexp-quote label)))
    (let ((m1 (string-match
               (concat "\\(?:^\\|\\n\\)" jupiterweb--blank-re "*"
                       escaped jupiterweb--blank-re "*:" jupiterweb--blank-re
                       "*\\n+" jupiterweb--blank-re "*\\([^\n]*\\)")
               text)))
      (if m1
          (let ((val (jupiterweb--clean-field-text (match-string 1 text))))
            (if (or (null val)
                    (member (downcase val)
                            (mapcar #'downcase jupiterweb--syllabus-delimiter-labels)))
                nil
              val))
        (let ((m2 (string-match
                   (concat escaped jupiterweb--blank-re "*:" jupiterweb--blank-re
                           "*\\([^\n]+\\)")
                   text)))
          (if m2
              (let ((val (jupiterweb--clean-field-text (match-string 1 text))))
                (if (or (null val)
                        (member (downcase val)
                                (mapcar #'downcase jupiterweb--syllabus-delimiter-labels)))
                    nil
                  val))
            nil))))))

(defun jupiterweb--extract-instructors (text)
  "Convert \"12345 - Name\" occurrences into structured instructor records."
  (if (or (null text) (string-empty-p text))
      nil
    (let ((cleaned (jupiterweb--clean-field-text text)))
      (if (null cleaned)
          nil
        (let ((instructors nil)
              (regexp "\\([0-9]\\{3,\\}\\)\\s-*-\\s-*\\(.*?\\)\\(?:\\s-+[0-9]\\{3,\\}\\s-*-\\|$\\)")
              (pos 0))
          (while (string-match regexp cleaned pos)
            (let ((code (match-string 1 cleaned))
                  (name (jupiterweb--clean-field-text (match-string 2 cleaned))))
              (when (and code name)
                (push (list :code code :name name) instructors))
              (setq pos (match-end 0))))
          (nreverse instructors))))))

(defun jupiterweb--clean-record (value)
  "Recursively clean strings in records."
  (cond
   ((null value) nil)
   ((stringp value) (jupiterweb--clean-field-text value))
   ((listp value)
    (mapcar #'jupiterweb--clean-record value))
   (t value)))

(defun jupiterweb--extract-query-param (url param)
  "Extract query parameter PARAM from URL, regardless of parameter order."
  (let ((case-fold-search t))
    (when (string-match
           (concat "[?&]" (regexp-quote param) "=\\([^&]+\\)")
           url)
      (match-string 1 url))))

(defun jupiterweb--html-cell-to-text (html)
  "Return cleaned plain text for one HTML cell fragment HTML."
  (jupiterweb--clean-field-text (jupiterweb--html-to-plain-text html)))

(defun jupiterweb-parse-curriculum (html)
  "Extract discipline records from a JupiterWeb curriculum HTML page."
  (let ((seen nil)
        (disciplines nil))
    (with-temp-buffer
      (insert html)
      (goto-char (point-min))
      (while (re-search-forward
              (concat "<a[^>]*href=\"[^\"]*obterDisciplina?[^\"]*sgldis=\\([^\"]*?\\)[&\"]"
                      ".*?>\\([^<]*\\)</a>"
                      "\\s-*</td>\\s-*<td[^>]*>\\(.*?\\)</td>")
              nil t)
        (let* ((raw-sgldis (match-string 1))
               (raw-link-text (match-string 2))
               (raw-name-cell (match-string 3))
               (sgldis (if raw-sgldis (jupiterweb--clean-field-text raw-sgldis) nil))
               (link-text (jupiterweb--clean-field-text raw-link-text))
               (name-cell (jupiterweb--html-cell-to-text raw-name-cell))
               (name (if (and name-cell
                              (not (string-empty-p name-cell))
                              (not (string= name-cell sgldis)))
                         name-cell
                       link-text)))
          (when (and sgldis
                     (not (member sgldis seen))
                     (not (string-empty-p sgldis)))
            (push sgldis seen)
            (push (list :sgldis sgldis :name name) disciplines)))))
    (nreverse disciplines)))

(defun jupiterweb-parse-discipline (html &optional sgldis source-url)
  "Extract syllabus data from a JupiterWeb discipline HTML page."
  (let ((text (jupiterweb--html-to-plain-text html)))
    (if (or (null text)
            (not (string-match-p "Cr.ditos Aula" text))
            (not (string-match-p "Disciplina:" text)))
        nil
      (let ((unidade-grupo
             (when (string-match
                    (concat "Pr.-Reitoria de Gradua..o" jupiterweb--blank-re
                            "+\\(.*?\\)" jupiterweb--blank-re "+Disciplina:")
                    text)
               (match-string 1 text))))
        (let ((m-ident (string-match
                        (concat "Disciplina:" jupiterweb--blank-re
                                "*\\([^\n-]+?\\)" jupiterweb--blank-re "*-"
                                jupiterweb--blank-re "*\\([^\n]+\\)")
                        text)))
          (if (not m-ident)
              nil
            (let* ((raw-sgldis (match-string 1 text))
                   (raw-name (match-string 2 text))
                   (ident-end (match-end 0))
                   (sgldis-parsed (jupiterweb--clean-field-text raw-sgldis))
                   (nome-disciplina (jupiterweb--clean-field-text raw-name))
                   (nome-disciplina-ingles
                    (let ((lines (split-string (substring text ident-end) "\n"))
                          (found nil))
                      (while (and lines (not found))
                        (let ((line (jupiterweb--clean-field-text (car lines))))
                          (cond
                           ((null line) nil)
                           ((string-match-p "Cr.ditos Aula:" line)
                            (setq lines nil))
                           (t
                            (setq found line))))
                        (setq lines (cdr lines)))
                      found)))
              (let* ((u-parts (when unidade-grupo (split-string unidade-grupo "\n")))
                     (u-clean (delq nil (mapcar #'jupiterweb--clean-field-text u-parts)))
                     (unidade (jupiterweb--normalize-unit (car u-clean)))
                     (grupo (cadr u-clean))
                     (cred-aula (jupiterweb--extract-number
                                 text (concat "Cr.ditos" jupiterweb--blank-re
                                              "+Aula:" jupiterweb--blank-re
                                              "*\\([0-9]+\\)")))
                     (cred-trabalho (jupiterweb--extract-number
                                     text (concat "Cr.ditos" jupiterweb--blank-re
                                                  "+Trabalho:" jupiterweb--blank-re
                                                  "*\\([0-9]+\\)")))
                     (carga-total (jupiterweb--extract-number
                                   text (concat "Carga" jupiterweb--blank-re
                                                "+Hor.ria" jupiterweb--blank-re
                                                "+Total:" jupiterweb--blank-re
                                                "*\\([0-9]+\\)"))))
                (if (or (null cred-aula) (null cred-trabalho) (null carga-total))
                    nil
                  (let* ((m-extra (string-match
                                  (concat "Carga" jupiterweb--blank-re "+Hor.ria"
                                          jupiterweb--blank-re "+Total:"
                                          jupiterweb--blank-re "*[0-9]+"
                                          jupiterweb--blank-re "*h"
                                          jupiterweb--blank-re "*\\(.*?\\)"
                                          jupiterweb--blank-re "*Tipo:")
                                  text))
                         (extra (if m-extra (jupiterweb--clean-field-text (match-string 1 text)) ""))
                         (ch-pcc (jupiterweb--extract-number
                                  text (concat "Pr.ticas" jupiterweb--blank-re
                                               "+como" jupiterweb--blank-re
                                               "+Componentes" jupiterweb--blank-re
                                               "+Curriculares:" jupiterweb--blank-re
                                               "*\\([0-9]+\\)")))
                         (ch-estagio (jupiterweb--extract-number (or extra "")
                                       (concat "Est.gio:" jupiterweb--blank-re
                                               "*\\([0-9]+\\)")))
                         (ch-ext (jupiterweb--extract-number
                                  text (concat "Carga" jupiterweb--blank-re
                                               "+Hor.ria" jupiterweb--blank-re
                                               "+de" jupiterweb--blank-re
                                               "+Extens.o:" jupiterweb--blank-re
                                               "*\\([0-9]+\\)")))
                         (secoes (jupiterweb--extract-sections text))
                         (get-section (lambda (key) (cdr (assoc key secoes))))
                         (docentes-texto (funcall get-section "docente_s_responsavel_eis")))
                    (when (not (funcall get-section "conteudo_programatico"))
                      (setq secoes
                            (cons (cons "conteudo_programatico"
                                        (funcall get-section "programa"))
                                  secoes)))
                    (jupiterweb--clean-record
                     (list :sgldis sgldis-parsed
                           :name nome-disciplina
                           :name-en nome-disciplina-ingles
                           :unit unidade
                           :group grupo
                           :credits-lecture cred-aula
                           :credits-work cred-trabalho
                           :workload-total carga-total
                           :workload-pcc ch-pcc
                           :workload-internship ch-estagio
                           :workload-extension ch-ext
                           :extra extra
                           :type (jupiterweb--extract-label-value text "Tipo")
                           :activation (jupiterweb--extract-label-value text "Ativação")
                           :deactivation (jupiterweb--extract-label-value text "Desativação")
                           :syllabus (funcall get-section "ementa")
                           :objectives (funcall get-section "objetivos")
                           :summary-program (funcall get-section "conteudo_programatico")
                           :program (funcall get-section "programa")
                           :teaching-method (funcall get-section "metodo_de_ensino")
                           :assessment-method (funcall get-section "criterio_de_avaliacao")
                           :recovery-rule (funcall get-section "norma_de_recuperacao")
                           :bibliography (funcall get-section "bibliografia")
                           :basic-bibliography (funcall get-section "bibliografia_basica")
                           :complementary-bibliography (funcall get-section "bibliografia_complementar")
                           :sustainable-development-goals (funcall get-section "objetivos_de_desenvolvimento_sustentavel_onu")
                           :instructors docentes-texto
                           :instructors-list (jupiterweb--extract-instructors docentes-texto)
                           :source-url source-url))))))))))))

(defun jupiterweb--build-syllabus-fallback (sgldis &optional name observation)
  "Build a fallback syllabus record for provisional or failed disciplines."
  (list :sgldis sgldis
        :name (or name nil)
        :name-en nil
        :unit nil
        :group nil
        :credits-lecture nil
        :credits-work nil
        :workload-total nil
        :workload-pcc nil
        :workload-internship nil
        :workload-extension nil
        :extra nil
        :type nil
        :activation nil
        :deactivation nil
        :syllabus nil
        :objectives nil
        :summary-program nil
        :program nil
        :teaching-method nil
        :assessment-method nil
        :recovery-rule nil
        :bibliography nil
        :basic-bibliography nil
        :complementary-bibliography nil
        :sustainable-development-goals nil
        :instructors nil
        :instructors-list nil
        :syllabus-status "fallback"
        :observation (or observation "Discipline not found or not parseable.")))

(provide 'jupiterweb-parse)
;;; jupiterweb-parse.el ends here