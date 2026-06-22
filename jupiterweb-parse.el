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

(defun jupiterweb--fix-cp1252-controls (text)
  "Fix common CP1252 control characters."
  (error "jupiterweb--fix-cp1252-controls not yet implemented"))

(defun jupiterweb--normalize-unicode (text)
  "Remove invisible spaces and normalize Unicode."
  (error "jupiterweb--normalize-unicode not yet implemented"))

(defun jupiterweb--convert-double-quotes (text)
  "Convert safe internal straight quotes to typographic quotes."
  (error "jupiterweb--convert-double-quotes not yet implemented"))

(defun jupiterweb--clean-field-text (text &optional preserve-breaks)
  "Clean a parsed field."
  (error "jupiterweb--clean-field-text not yet implemented"))

(defun jupiterweb--html-to-plain-text (html)
  "Convert HTML to text while preserving section heading line breaks."
  (error "jupiterweb--html-to-plain-text not yet implemented"))

(defun jupiterweb--normalize-key (title)
  "Convert Portuguese headings to ASCII keys."
  (error "jupiterweb--normalize-key not yet implemented"))

(defun jupiterweb--to-integer (value)
  "Convert VALUE to an integer, returning nil if empty or invalid."
  (error "jupiterweb--to-integer not yet implemented"))

(defun jupiterweb--extract-number (text regexp)
  "Search TEXT for REGEXP and return the first capture group as an integer."
  (error "jupiterweb--extract-number not yet implemented"))

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