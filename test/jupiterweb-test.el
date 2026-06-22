;;; jupiterweb-test.el --- ERT tests for jupiterweb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; ERT tests for the jupiterweb package.
;; Tests run offline by default.  Network tests are disabled unless
;; `jupiterweb-test-enable-network' is non-nil.

;;; Code:

(require 'ert)
(require 'jupiterweb)

(defcustom jupiterweb-test-enable-network nil
  "When non-nil, allow tests to access JupiterWeb."
  :type 'boolean
  :group 'jupiterweb)

;;; URL builders

(ert-deftest jupiterweb-test-grade-url ()
  "Test that `jupiterweb--grade-url' builds the correct curriculum URL."
  (should (equal (jupiterweb--grade-url)
                 "https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=43&codcur=43031&codhab=0&tipo=N"))
  ;; With explicit arguments
  (should (equal (jupiterweb--grade-url "43" "43031" "0" "N")
                 "https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=43&codcur=43031&codhab=0&tipo=N"))
  ;; With different course
  (should (equal (jupiterweb--grade-url "17" "17001" "0" "N")
                 "https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=17&codcur=17001&codhab=0&tipo=N")))

(ert-deftest jupiterweb-test-discipline-url ()
  "Test that `jupiterweb--discipline-url' builds the correct discipline URL."
  (should (equal (jupiterweb--discipline-url "4300151")
                 "https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=4300151&codcur=43031&codhab=0"))
  ;; With explicit arguments
  (should (equal (jupiterweb--discipline-url "4300151" "43031" "0")
                 "https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=4300151&codcur=43031&codhab=0"))
  ;; Different discipline and course
  (should (equal (jupiterweb--discipline-url "4300152" "43031" "4")
                 "https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=4300152&codcur=43031&codhab=4")))

(ert-deftest jupiterweb-test-current-course-key ()
  "Test that `jupiterweb--current-course-key' returns the correct key."
  (should (equal (jupiterweb--current-course-key) '("43031" . "0"))))

;;; Course setting and memory invalidation

(ert-deftest jupiterweb-test-set-course-invalidates-memory ()
  "Test that `jupiterweb-set-course' updates variables and clears in-memory cache."
  ;; Set up in-memory caches with dummy data.
  (setq jupiterweb--curriculum-memory '(:dummy curriculum)
        jupiterweb--discipline-memory '(("4300151" . (:dummy discipline))))
  ;; Set a new course.
  (jupiterweb-set-course :codcg "43" :codcur "43031" :codhab "0" :tipo "N")
  ;; Variables should be updated.
  (should (equal jupiterweb-codcur "43031"))
  (should (equal jupiterweb-codhab "0"))
  ;; In-memory caches should be cleared.
  (should (null jupiterweb--curriculum-memory))
  (should (null jupiterweb--discipline-memory))
  ;; Test partial update — only change codhab.
  (setq jupiterweb--curriculum-memory '(:dummy))
  (jupiterweb-set-course :codhab "4")
  (should (equal jupiterweb-codhab "4"))
  (should (null jupiterweb--curriculum-memory))
  ;; Restore defaults.
  (jupiterweb-set-course :codcg "43" :codcur "43031" :codhab "0" :tipo "N"))

;;; CP1252 control-character mapping

(ert-deftest jupiterweb-test-cp1252-control-mapping ()
  "Test that CP1252 control characters are converted to proper Unicode."
  ;; Test curly quotes (the most common case)
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF91 #x68 #x65 #x6C #x6C #x6F #x3FFF92))
                 (string ?\u2018 ?h ?e ?l ?l ?o ?\u2019)))
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF93 ?q ?u ?o ?t ?e ?d #x3FFF94))
                 (string ?\u201C ?q ?u ?o ?t ?e ?d ?\u201D)))
  ;; Test en-dash and em-dash
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF96 #x3FFF97))
                 (string ?\u2013 ?\u2014)))
  ;; Test bullet
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF95))
                 (string ?\u2022)))
  ;; Test ellipsis
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF85))
                 (string ?\u2026)))
  ;; Test Euro sign
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF80))
                 (string ?\u20AC)))
  ;; Test trademark
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF99))
                 (string ?\u2122)))
  ;; Test that regular ASCII is untouched
  (should (equal (jupiterweb--fix-cp1252-controls "hello world")
                 "hello world"))
  ;; Test mixed content
  (should (equal (jupiterweb--fix-cp1252-controls
                  (string ?P ?r ?i ?c ?e ?: ?  #x3FFF80 ?5 ?  #x3FFF96 ?  ?s ?p ?e ?c ?i ?a ?l #x3FFF99))
                 (string ?P ?r ?i ?c ?e ?: ?  ?\u20AC ?5 ?  ?\u2013 ?  ?s ?p ?e ?c ?i ?a ?l ?\u2122)))
  ;; Test empty string and nil
  (should (equal (jupiterweb--fix-cp1252-controls "") ""))
  (should (null (jupiterweb--fix-cp1252-controls nil))))

;;; Invisible-space normalization

(ert-deftest jupiterweb-test-invisible-space-normalization ()
  "Test that invisible spaces are removed or converted to normal spaces."
  ;; NO-BREAK SPACE → space
  (should (equal (jupiterweb--normalize-unicode "hello\u00A0world")
                 "hello world"))
  ;; EN SPACE → space
  (should (equal (jupiterweb--normalize-unicode "a\u2002b")
                 "a b"))
  ;; EM SPACE → space
  (should (equal (jupiterweb--normalize-unicode "a\u2003b")
                 "a b"))
  ;; THIN SPACE → space
  (should (equal (jupiterweb--normalize-unicode "a\u2009b")
                 "a b"))
  ;; HAIR SPACE → space
  (should (equal (jupiterweb--normalize-unicode "a\u200Ab")
                 "a b"))
  ;; IDEOGRAPHIC SPACE → space
  (should (equal (jupiterweb--normalize-unicode "a\u3000b")
                 "a b"))
  ;; NARROW NO-BREAK SPACE → space
  (should (equal (jupiterweb--normalize-unicode "a\u202Fb")
                 "a b"))
  ;; MEDIUM MATHEMATICAL SPACE → space
  (should (equal (jupiterweb--normalize-unicode "a\u205Fb")
                 "a b"))
  ;; ZERO WIDTH SPACE → removed
  (should (equal (jupiterweb--normalize-unicode "hello\u200Bworld")
                 "helloworld"))
  ;; ZERO WIDTH NON-JOINER → removed
  (should (equal (jupiterweb--normalize-unicode "hello\u200Cworld")
                 "helloworld"))
  ;; ZERO WIDTH JOINER → removed
  (should (equal (jupiterweb--normalize-unicode "hello\u200Dworld")
                 "helloworld"))
  ;; SOFT HYPHEN → removed
  (should (equal (jupiterweb--normalize-unicode "hello\u00ADworld")
                 "helloworld"))
  ;; BOM → removed
  (should (equal (jupiterweb--normalize-unicode "\uFEFFhello")
                 "hello"))
  ;; Multiple invisible spaces together (NBSP→space, ZWS→removed, THIN→space = two spaces)
  (should (equal (jupiterweb--normalize-unicode "a\u00A0\u200B\u2009b")
                 "a  b"))
  ;; Regular text unchanged
  (should (equal (jupiterweb--normalize-unicode "hello world")
                 "hello world"))
  ;; Empty string and nil
  (should (equal (jupiterweb--normalize-unicode "") ""))
  (should (null (jupiterweb--normalize-unicode nil))))

;;; Field text cleanup

(ert-deftest jupiterweb-test-clean-field-text ()
  "Test that `jupiterweb--clean-field-text' cleans fields correctly."
  ;; Basic whitespace normalization.
  (should (equal (jupiterweb--clean-field-text "  hello   world  ")
                 "hello world"))
  ;; Literal \\n, \\r, \\t sequences removed.
  (should (equal (jupiterweb--clean-field-text "hello\\nworld")
                 "hello world"))
  (should (equal (jupiterweb--clean-field-text "hello\\r\\nworld")
                 "hello world"))
  (should (equal (jupiterweb--clean-field-text "hello\\tworld")
                 "hello world"))
  ;; Stray backslashes removed.
  (should (equal (jupiterweb--clean-field-text "hello\\world")
                 "hello world"))
  ;; HTML entities unescaped (double, like Python).
  (should (equal (jupiterweb--clean-field-text "&amp;amp;hello")
                 "&hello"))
  (should (equal (jupiterweb--clean-field-text "&lt;b&gt;bold&lt;/b&gt;")
                 "<b>bold</b>"))
  ;; nil → nil.
  (should (null (jupiterweb--clean-field-text nil)))
  ;; Empty string → nil.
  (should (null (jupiterweb--clean-field-text "")))
  ;; Whitespace only → nil.
  (should (null (jupiterweb--clean-field-text "   ")))
  ;; Stripping semicolons and colons from edges.
  (should (equal (jupiterweb--clean-field-text ";:hello;:")
                 "hello"))
  ;; Preserve breaks mode.
  (should (equal (jupiterweb--clean-field-text "line1\n\n\nline2" t)
                 "line1\n\nline2"))
  ;; Double quotes converted to typographic quotes.
  (should (equal (jupiterweb--clean-field-text "say \"hello\" now")
                 "say \u201Chello\u201D now")))

(provide 'jupiterweb-test)
;;; jupiterweb-test.el ends here