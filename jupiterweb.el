;;; jupiterweb.el --- Query, cache, view, insert, and export USP JupiterWeb data  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; Author: rodrigues-am <rodrigues.am@usp.br>
;; Keywords: convenience, comm, tools
;; URL: https://github.com/rodrigues-am/jupiterweb
;; Package-Requires: ((emacs "27.1"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; jupiterweb is an Emacs Lisp package for querying, caching, viewing,
;; inserting, and exporting curriculum and discipline syllabus data from
;; USP JupiterWeb.
;;
;; The package supports the Physics Teaching Degree curriculum by default
;; while allowing other USP courses through customizable variables.
;;
;; See SPEC.md for the full technical specification.

;;; Code:

(require 'jupiterweb-vars)
(require 'jupiterweb-http)
(require 'jupiterweb-parse)
(require 'jupiterweb-cache)
(require 'jupiterweb-ui)
(require 'jupiterweb-export)

;; Public autoloads will be added as commands are implemented.

(provide 'jupiterweb)
;;; jupiterweb.el ends here