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

(provide 'jupiterweb-test)
;;; jupiterweb-test.el ends here