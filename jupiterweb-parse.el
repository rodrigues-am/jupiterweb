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
  "Decode a JupiterWeb HTTP response robustly."
  (error "jupiterweb--decode-response not yet implemented"))

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

(defun jupiterweb--html-unescape (text)
  "HTML-unescape TEXT.
Convert HTML entities like &amp;, &lt;, &gt;, &quot;, &#NNN;, &#xHHH;,
and &nbsp; to their character equivalents.  Applied twice for nested entities."
  (if (or (null text) (string-empty-p text))
      text
    (with-temp-buffer
      (insert text)
      (dotimes (_ 2)
        (goto-char (point-min))
        (while (re-search-forward "&\\(#\\([0-9]+\\)\\|#x\\([0-9a-fA-F]+\\)\\|\\(amp\\|lt\\|gt\\|quot\\|nbsp\\|apos\\);\\)" nil t)
          (let ((match (match-string 1))
                (num (match-string 2))
                (hex (match-string 3))
                (name (match-string 4)))
            (cond
             (num
              (replace-match (string (string-to-number num)) t t))
             (hex
              (replace-match (string (string-to-number hex 16)) t t))
             (t
              (replace-match
               (pcase name
                 ("amp" "&")
                 ("lt" "<")
                 ("gt" ">")
                 ("quot" "\"")
                 ("nbsp" " ")
                 ("apos" "'")
                 (_ match))
               t t))))))
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
  (error "jupiterweb--normalize-unit not yet implemented"))

(defun jupiterweb--heading-regexp (title)
  "Return a regexp matching an isolated section heading line for TITLE."
  (error "jupiterweb--heading-regexp not yet implemented"))

(defun jupiterweb--extract-section (text title)
  "Extract the content of section TITLE from TEXT, stopping at the next heading."
  (error "jupiterweb--extract-section not yet implemented"))

(defun jupiterweb--extract-sections (text)
  "Extract all known sections from TEXT."
  (error "jupiterweb--extract-sections not yet implemented"))

(defun jupiterweb--extract-label-value (text label)
  "Extract a short label value from TEXT without capturing the next heading."
  (error "jupiterweb--extract-label-value not yet implemented"))

(defun jupiterweb--extract-instructors (text)
  "Convert \"12345 - Name\" occurrences into structured instructor records."
  (error "jupiterweb--extract-instructors not yet implemented"))

(defun jupiterweb--clean-record (value)
  "Recursively clean strings in records."
  (error "jupiterweb--clean-record not yet implemented"))

(defun jupiterweb-parse-curriculum (html)
  "Extract discipline records from a JupiterWeb curriculum HTML page."
  (error "jupiterweb-parse-curriculum not yet implemented"))

(defun jupiterweb-parse-discipline (html &optional sgldis source-url)
  "Extract syllabus data from a JupiterWeb discipline HTML page."
  (error "jupiterweb-parse-discipline not yet implemented"))

(defun jupiterweb--build-syllabus-fallback (sgldis &optional name observation)
  "Build a fallback syllabus record for provisional or failed disciplines."
  (error "jupiterweb--build-syllabus-fallback not yet implemented"))

(provide 'jupiterweb-parse)
;;; jupiterweb-parse.el ends here