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

;; Tests will be added as features are implemented.

(provide 'jupiterweb-test)
;;; jupiterweb-test.el ends here