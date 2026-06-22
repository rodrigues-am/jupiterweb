;;; jupiterweb-test.el --- ERT tests for jupiterweb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; ERT tests for the jupiterweb package.
;; Tests run offline by default.

;;; Code:

(require 'ert)
(require 'jupiterweb)
(require 'jupiterweb-http)

(defcustom jupiterweb-test-enable-network nil
  "When non-nil, allow tests to access JupiterWeb."
  :type 'boolean
  :group 'jupiterweb)

;;; URL builders

(ert-deftest jupiterweb-test-grade-url ()
  "Test that `jupiterweb--grade-url' builds the correct curriculum URL."
  (should (equal (jupiterweb--grade-url)
                 "https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=43&codcur=43031&codhab=0&tipo=N"))
  (should (equal (jupiterweb--grade-url "43" "43031" "0" "N")
                 "https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=43&codcur=43031&codhab=0&tipo=N"))
  (should (equal (jupiterweb--grade-url "17" "17001" "0" "N")
                 "https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=17&codcur=17001&codhab=0&tipo=N")))

(ert-deftest jupiterweb-test-discipline-url ()
  "Test that `jupiterweb--discipline-url' builds the correct discipline URL."
  (should (equal (jupiterweb--discipline-url "4300151")
                 "https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=4300151&codcur=43031&codhab=0"))
  (should (equal (jupiterweb--discipline-url "4300151" "43031" "0")
                 "https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=4300151&codcur=43031&codhab=0"))
  (should (equal (jupiterweb--discipline-url "4300152" "43031" "4")
                 "https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=4300152&codcur=43031&codhab=4")))

(ert-deftest jupiterweb-test-current-course-key ()
  "Test that `jupiterweb--current-course-key' returns the correct key."
  (should (equal (jupiterweb--current-course-key) '("43031" . "0"))))

;;; Course setting and memory invalidation

(ert-deftest jupiterweb-test-set-course-invalidates-memory ()
  "Test that `jupiterweb-set-course' updates variables and clears in-memory cache."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-set-course/"))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (setq jupiterweb--curriculum-memory '(:dummy curriculum)
          jupiterweb--discipline-memory '(("4300151" . (:dummy discipline))))
    (jupiterweb-set-course :codcg "43" :codcur "43031" :codhab "0" :tipo "N")
    (should (equal jupiterweb-codcur "43031"))
    (should (equal jupiterweb-codhab "0"))
    (should (null jupiterweb--curriculum-memory))
    (should (null jupiterweb--discipline-memory))
    (setq jupiterweb--curriculum-memory '(:dummy))
    (jupiterweb-set-course :codhab "4")
    (should (equal jupiterweb-codhab "4"))
    (should (null jupiterweb--curriculum-memory))
    (jupiterweb-set-course :codcg "43" :codcur "43031" :codhab "0" :tipo "N")
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

;;; CP1252 control-character mapping

(ert-deftest jupiterweb-test-cp1252-control-mapping ()
  "Test that CP1252 control characters are converted to proper Unicode."
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF91 #x68 #x65 #x6C #x6C #x6F #x3FFF92))
                 (string ?\u2018 ?h ?e ?l ?l ?o ?\u2019)))
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF93 ?q ?u ?o ?t ?e ?d #x3FFF94))
                 (string ?\u201C ?q ?u ?o ?t ?e ?d ?\u201D)))
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF96 #x3FFF97))
                 (string ?\u2013 ?\u2014)))
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF95))
                 (string ?\u2022)))
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF85))
                 (string ?\u2026)))
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF80))
                 (string ?\u20AC)))
  (should (equal (jupiterweb--fix-cp1252-controls (string #x3FFF99))
                 (string ?\u2122)))
  (should (equal (jupiterweb--fix-cp1252-controls "hello world")
                 "hello world"))
  (should (equal (jupiterweb--fix-cp1252-controls "") ""))
  (should (null (jupiterweb--fix-cp1252-controls nil))))

;;; Invisible-space normalization

(ert-deftest jupiterweb-test-invisible-space-normalization ()
  "Test that invisible spaces are removed or converted to normal spaces."
  (should (equal (jupiterweb--normalize-unicode "hello\u00A0world")
                 "hello world"))
  (should (equal (jupiterweb--normalize-unicode "a\u2002b") "a b"))
  (should (equal (jupiterweb--normalize-unicode "a\u2003b") "a b"))
  (should (equal (jupiterweb--normalize-unicode "a\u2009b") "a b"))
  (should (equal (jupiterweb--normalize-unicode "a\u200Ab") "a b"))
  (should (equal (jupiterweb--normalize-unicode "a\u3000b") "a b"))
  (should (equal (jupiterweb--normalize-unicode "a\u202Fb") "a b"))
  (should (equal (jupiterweb--normalize-unicode "a\u205Fb") "a b"))
  (should (equal (jupiterweb--normalize-unicode "hello\u200Bworld") "helloworld"))
  (should (equal (jupiterweb--normalize-unicode "hello\u200Cworld") "helloworld"))
  (should (equal (jupiterweb--normalize-unicode "hello\u200Dworld") "helloworld"))
  (should (equal (jupiterweb--normalize-unicode "hello\u00ADworld") "helloworld"))
  (should (equal (jupiterweb--normalize-unicode "\uFEFFhello") "hello"))
  (should (equal (jupiterweb--normalize-unicode "a\u00A0\u200B\u2009b") "a  b"))
  (should (equal (jupiterweb--normalize-unicode "hello world") "hello world"))
  (should (equal (jupiterweb--normalize-unicode "") ""))
  (should (null (jupiterweb--normalize-unicode nil))))

;;; Field text cleanup

(ert-deftest jupiterweb-test-clean-field-text ()
  "Test that `jupiterweb--clean-field-text' cleans fields correctly."
  (should (equal (jupiterweb--clean-field-text "  hello   world  ")
                 "hello world"))
  (should (equal (jupiterweb--clean-field-text "hello\\nworld")
                 "hello world"))
  (should (equal (jupiterweb--clean-field-text "hello\\r\\nworld")
                 "hello world"))
  (should (equal (jupiterweb--clean-field-text "hello\\tworld")
                 "hello world"))
  (should (equal (jupiterweb--clean-field-text "hello\\world")
                 "hello world"))
  (should (equal (jupiterweb--clean-field-text "&amp;amp;hello")
                 "&hello"))
  (should (equal (jupiterweb--clean-field-text "&lt;b&gt;bold&lt;/b&gt;")
                 "<b>bold</b>"))
  (should (null (jupiterweb--clean-field-text nil)))
  (should (null (jupiterweb--clean-field-text "")))
  (should (null (jupiterweb--clean-field-text "   ")))
  (should (equal (jupiterweb--clean-field-text ";:hello;:")
                 "hello"))
  (should (equal (jupiterweb--clean-field-text "line1\n\n\nline2" t)
                 "line1\n\nline2"))
  (should (equal (jupiterweb--clean-field-text "say \"hello\" now")
                 "say \u201Chello\u201D now")))

;;; HTML-to-plain-text conversion

(ert-deftest jupiterweb-test-html-to-plain-text ()
  "Test that `jupiterweb--html-to-plain-text' converts HTML correctly."
  (should (equal (jupiterweb--html-to-plain-text
                  "<script>alert(1)</script>hello") "hello"))
  (should (equal (jupiterweb--html-to-plain-text
                  "<style>.x{color:red}</style>hello") "hello"))
  (should (equal (jupiterweb--html-to-plain-text "line1<br>line2")
                 "line1\nline2"))
  (should (equal (jupiterweb--html-to-plain-text "line1<br/>line2")
                 "line1\nline2"))
  (should (equal (jupiterweb--html-to-plain-text "line1<br />line2")
                 "line1\nline2"))
  (should (equal (jupiterweb--html-to-plain-text "<p>para1</p><p>para2</p>")
                 "para1\npara2"))
  (should (equal (jupiterweb--html-to-plain-text "<div>a</div><div>b</div>")
                 "a\nb"))
  (should (equal (jupiterweb--html-to-plain-text "<h1>Title</h1>body")
                 "Title\nbody"))
  (should (equal (jupiterweb--html-to-plain-text "<li>item1</li><li>item2</li>")
                 "- item1\n\n- item2"))
  (should (equal (jupiterweb--html-to-plain-text "<td>a</td><td>b</td>")
                 "a b"))
  (should (equal (jupiterweb--html-to-plain-text "<b>bold</b>")
                 "bold"))
  (should (equal (jupiterweb--html-to-plain-text "&lt;p&gt;text&lt;/p&gt;")
                 "<p>text</p>"))
  (should (equal (jupiterweb--html-to-plain-text
                  "<p>Some text</p>\n<h2>Ementa</h2>\n<p>Syllabus content</p>")
                 "Some text\n\nEmenta\n\nSyllabus content"))
  (should (equal (jupiterweb--html-to-plain-text "hello    world")
                 "hello world"))
  (should (equal (jupiterweb--html-to-plain-text "a\n\n\n\nb")
                 "a\n\nb"))
  (should (null (jupiterweb--html-to-plain-text nil)))
  (should (equal (jupiterweb--html-to-plain-text "") "")))

;;; Key and integer helpers

(ert-deftest jupiterweb-test-normalize-key ()
  "Test that `jupiterweb--normalize-key' converts accented headings to ASCII keys."
  (should (equal (jupiterweb--normalize-key "Ementa") "ementa"))
  (should (equal (jupiterweb--normalize-key "Objetivos") "objetivos"))
  (should (equal (jupiterweb--normalize-key "Conteudo Programatico")
                 "conteudo_programatico"))
  (should (equal (jupiterweb--normalize-key "Metodo de Ensino")
                 "metodo_de_ensino"))
  (should (equal (jupiterweb--normalize-key "Criterio de Avaliacao")
                 "criterio_de_avaliacao"))
  (should (equal (jupiterweb--normalize-key "Norma de Recuperacao")
                 "norma_de_recuperacao"))
  (should (equal (jupiterweb--normalize-key "Bibliografia Basica")
                 "bibliografia_basica"))
  (should (equal (jupiterweb--normalize-key "Objetivos de Desenvolvimento Sustentavel (ONU)")
                 "objetivos_de_desenvolvimento_sustentavel_onu"))
  (should (equal (jupiterweb--normalize-key "Docente(s) Responsavel(eis)")
                 "docente_s_responsavel_eis"))
  (should (equal (jupiterweb--normalize-key "") ""))
  (should (equal (jupiterweb--normalize-key nil) ""))
  (should (equal (jupiterweb--normalize-key "  hello  ") "hello")))

(ert-deftest jupiterweb-test-to-integer ()
  "Test that `jupiterweb--to-integer' converts numeric strings to integers."
  (should (equal (jupiterweb--to-integer "42") 42))
  (should (equal (jupiterweb--to-integer "  42  ") 42))
  (should (equal (jupiterweb--to-integer "4.5") 4))
  (should (equal (jupiterweb--to-integer "0") 0))
  (should (null (jupiterweb--to-integer "")))
  (should (null (jupiterweb--to-integer "   ")))
  (should (null (jupiterweb--to-integer nil)))
  (should (equal (jupiterweb--to-integer 42) 42)))

;;; Curriculum parser

(ert-deftest jupiterweb-test-parse-curriculum-uses-name-from-next-td ()
  "Test that curriculum parser uses the discipline name cell, not link text."
  (let* ((html "<tr><td><a href=\"obterDisciplina?sgldis=4300157&codcur=43031&codhab=0\" class=\"link_gray\">4300157</a></td><td> Ciência, Educação e Linguagem</td></tr>")
         (disciplines (jupiterweb-parse-curriculum html))
         (first (car disciplines)))
    (should (equal (plist-get first :sgldis) "4300157"))
    (should (equal (plist-get first :name) "Ciência, Educação e Linguagem"))))

;;; Discipline parser

(ert-deftest jupiterweb-test-html-unescape-latin-named-entities ()
  "Test that Latin named HTML entities from JupiterWeb are decoded."
  (should (equal (jupiterweb--html-unescape
                  "Cr&eacute;ditos Aula &ccedil;&atilde;o &amp;eacute;")
                 "Créditos Aula ção é")))

(ert-deftest jupiterweb-test-parse-discipline-realistic-jupiterweb-html ()
  "Test parsing discipline metadata and sections from JupiterWeb-like HTML."
  (let* ((html "<html><body>
Pr&oacute;-Reitoria de Gradua&ccedil;&atilde;o<br>
IF - Instituto de F&iacute;sica<br>
Departamento de F&iacute;sica Aplicada<br>
Disciplina: 4300157 - Ci&ecirc;ncia, Educa&ccedil;&atilde;o e Linguagem<br><br>
Science, Education and Language<br><br>
Cr&eacute;ditos Aula:<br><br>2<br><br>
Cr&eacute;ditos Trabalho:<br><br>1<br><br>
Carga Hor&aacute;ria Total:<br><br>60 h<br>(<br><br>
Pr&aacute;ticas como Componentes Curriculares: 30 h<br><br>)<br><br>
Tipo:<br><br>Semestral<br><br>
Ativa&ccedil;&atilde;o:<br><br>01/01/2019<br><br>
Desativa&ccedil;&atilde;o:<br><br>
Ementa<br><br>Concep&ccedil;&otilde;es de Ci&ecirc;ncia e Ensino.<br><br>
Objetivos<br><br>Discutir letramento cient&iacute;fico.<br><br>
Conte&uacute;do Program&aacute;tico<br><br>Linguagem e ci&ecirc;ncia.<br><br>
Crit&eacute;rio de Avalia&ccedil;&atilde;o<br><br>Produ&ccedil;&otilde;es realizadas pelos estudantes.<br><br>
Bibliografia<br><br>ALMEIDA, M.J.P.M. Discursos da Ci&ecirc;ncia.<br>
</body></html>")
         (parsed (jupiterweb-parse-discipline html "4300157" "fixture-url")))
    (should parsed)
    (should (equal (plist-get parsed :sgldis) "4300157"))
    (should (equal (plist-get parsed :name) "Ciência, Educação e Linguagem"))
    (should (equal (plist-get parsed :name-en) "Science, Education and Language"))
    (should (equal (plist-get parsed :credits-lecture) 2))
    (should (equal (plist-get parsed :credits-work) 1))
    (should (equal (plist-get parsed :workload-total) 60))
    (should (equal (plist-get parsed :workload-pcc) 30))
    (should (equal (plist-get parsed :type) "Semestral"))
    (should (equal (plist-get parsed :activation) "01/01/2019"))
    (should (string-match-p "Concepções" (plist-get parsed :syllabus)))
    (should (string-match-p "letramento" (plist-get parsed :objectives)))
    (should (string-match-p "Linguagem" (plist-get parsed :summary-program)))
    (should (string-match-p "Produções" (plist-get parsed :assessment-method)))
    (should (string-match-p "Discursos da Ciência" (plist-get parsed :bibliography)))))

(ert-deftest jupiterweb-test-render-and-section-list-include-parsed-syllabus ()
  "Test view rendering and insertable section list include parsed fields."
  (let* ((data (list :sgldis "4300157"
                     :name "Ciência, Educação e Linguagem"
                     :credits-lecture 2
                     :credits-work 1
                     :workload-total 60
                     :activation "01/01/2019"
                     :syllabus "Ementa real"
                     :objectives "Objetivos reais"
                     :summary-program "Programa resumido"
                     :bibliography "Bibliografia real"))
         (rendered (jupiterweb--render-syllabus data))
         (sections (jupiterweb--section-list data)))
    (should (string-match-p "Credits Lecture:[[:space:]]+2" rendered))
    (should (string-match-p "Syllabus" rendered))
    (should (string-match-p "Ementa real" rendered))
    (should (assoc "Syllabus" sections))
    (should (assoc "Objectives" sections))
    (should (assoc "Bibliography" sections))))

(ert-deftest jupiterweb-test-render-syllabus-org-format ()
  "Test Org mode rendering has title, options, table, and section headings."
  (let* ((data (list :sgldis "4300157"
                     :name "Ciência, Educação e Linguagem"
                     :name-en "Science, Education and Language"
                     :credits-lecture 2
                     :credits-work 1
                     :workload-total 60
                     :workload-pcc 30
                     :type "Presencial"
                     :activation "01/01/2019"
                     :syllabus "Ementa real"
                     :objectives "Objetivos reais"
                     :summary-program "Programa resumido"
                     :bibliography "Bibliografia real"))
         (rendered (jupiterweb--render-syllabus-org data)))
    (should (string-match-p "#\\+title: Ci" rendered))
    (should (string-match-p "#\\+options: toc:nil num:nil" rendered))
    (should (string-match-p "#\\+latex_header" rendered))
    (should (string-match-p "| Field | Value |" rendered))
    (should (string-match-p "| Code | 4300157 |" rendered))
    (should (string-match-p "| Credits (Lecture) | 2 |" rendered))
    (should (string-match-p "| Total Workload | 60 h |" rendered))
    (should (string-match-p "| PCC Workload | 30 h |" rendered))
    (should (string-match-p "\\* Syllabus" rendered))
    (should (string-match-p "\\* Objectives" rendered))
    (should (string-match-p "\\* Bibliography" rendered))
    (should (string-match-p "Ementa real" rendered))
    ;; Should NOT include sections that are nil
    (should-not (string-match-p "\\* Teaching Method" rendered))
    (should-not (string-match-p "\\* Recovery Rule" rendered))))

;;; Cache filename helpers

(ert-deftest jupiterweb-test-cache-filenames ()
  "Test that cache filenames use fast Emacs Lisp cache files."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-cache/"))
    (should (equal (jupiterweb--cache-file-curriculum)
                   "/tmp/test-jupiterweb-cache/grade-codcg-43-codcur-43031-codhab-0-tipo-N.el"))
    (should (equal (jupiterweb--cache-file-discipline "4300151")
                   "/tmp/test-jupiterweb-cache/disciplina-4300151-codcur-43031-codhab-0.el"))))

;;; Cache roundtrip

(ert-deftest jupiterweb-test-cache-curriculum-roundtrip ()
  "Test that curriculum objects can be written and read from disk."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-cache-rt/"))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (jupiterweb--ensure-cache-directory)
    (let ((curriculum (list :package "jupiterweb"
                            :kind "curriculum"
                            :codcur "43031"
                            :disciplines (list (list :sgldis "4300151"
                                                     :name "Test Discipline")))))
      (jupiterweb-cache-write-curriculum curriculum)
      (should (jupiterweb-cache-curriculum-exists-p))
      (should (file-exists-p (jupiterweb--cache-file-curriculum)))
      (should-not (file-exists-p (jupiterweb--cache-file-curriculum-json)))
      (let ((read-back (jupiterweb-cache-read-curriculum)))
        (should (plist-get read-back :codcur))
        (should (equal (plist-get (car (plist-get read-back :disciplines)) :sgldis)
                       "4300151"))))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

(ert-deftest jupiterweb-test-cache-discipline-roundtrip ()
  "Test that discipline syllabus objects can be written and read from disk."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-cache-rt/"))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (jupiterweb--ensure-cache-directory)
    (let ((data (list :sgldis "4300151" :name "Test Discipline" :credits-lecture 4)))
      (jupiterweb-cache-write-discipline "4300151" data)
      (should (jupiterweb-cache-discipline-exists-p "4300151"))
      (should (file-exists-p (jupiterweb--cache-file-discipline "4300151")))
      (should-not (file-exists-p (jupiterweb--cache-file-discipline-json "4300151")))
      (let ((read-back (jupiterweb-cache-read-discipline "4300151")))
        (should read-back)
        (should (equal (plist-get read-back :sgldis) "4300151"))))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

(ert-deftest jupiterweb-test-cache-reads-legacy-json ()
  "Test that legacy JSON cache files are still readable."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-cache-json/"))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (jupiterweb--ensure-cache-directory)
    (let ((data (list :sgldis "4300151" :name "Legacy JSON Discipline")))
      (jupiterweb--json-write (jupiterweb--cache-file-discipline-json "4300151") data)
      (should (jupiterweb-cache-discipline-exists-p "4300151"))
      (let ((read-back (jupiterweb-cache-read-discipline "4300151")))
        (should (equal (plist-get read-back :name) "Legacy JSON Discipline"))))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

(ert-deftest jupiterweb-test-refresh-discipline-message-and-name-update ()
  "Test refresh announces discipline name and updates code-only curriculum names."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-refresh-msg/")
        (messages nil))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (setq jupiterweb--curriculum-memory
          (list :disciplines (list (list :sgldis "4300157"
                                         :name "Ciência, Educação e Linguagem"))))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages)))
              ((symbol-function 'jupiterweb-fetch-discipline-html)
               (lambda (_sgldis) "<html>fixture</html>"))
              ((symbol-function 'jupiterweb-parse-discipline)
               (lambda (_html sgldis _source-url)
                 (list :sgldis sgldis
                       :name "Ciência, Educação e Linguagem"
                       :credits-lecture 2
                       :objectives "Parsed objectives"))))
      (jupiterweb-refresh-discipline-cache "4300157")
      (should (member "JupiterWeb: buscando disciplina 4300157 - Ciência, Educação e Linguagem"
                      messages))
      (should (member "JupiterWeb: 🟩 Discipline 4300157 - Ciência, Educação e Linguagem loaded successfully!"
                      messages))
      (should (file-exists-p (jupiterweb--log-file)))
      (with-temp-buffer
        (insert-file-contents (jupiterweb--log-file))
        (should (string-match-p "kind=discipline status=success" (buffer-string)))
        (should (string-match-p "sgldis=\\\"4300157\\\"" (buffer-string))))
      (should (equal (plist-get (car (plist-get jupiterweb--curriculum-memory :disciplines)) :name)
                     "Ciência, Educação e Linguagem")))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

(ert-deftest jupiterweb-test-refresh-discipline-caches-named-fallback ()
  "Test refresh caches a named fallback when parsing fails."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-refresh-fallback/"))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (setq jupiterweb--curriculum-memory
          (list :disciplines (list (list :sgldis "4300157"
                                         :name "Ciência, Educação e Linguagem"))))
    (cl-letf (((symbol-function 'jupiterweb-fetch-discipline-html)
               (lambda (_sgldis) "<html>fixture</html>"))
              ((symbol-function 'jupiterweb-parse-discipline)
               (lambda (&rest _args) nil)))
      (let ((record (jupiterweb-refresh-discipline-cache "4300157")))
        (should (equal (plist-get record :name) "Ciência, Educação e Linguagem"))
        (should (equal (plist-get record :syllabus-status) "fallback"))
        (should (file-exists-p (jupiterweb--cache-file-discipline "4300157")))
        (should (equal (plist-get (jupiterweb-cache-read-discipline "4300157") :name)
                       "Ciência, Educação e Linguagem"))
        (with-temp-buffer
          (insert-file-contents (jupiterweb--log-file))
          (should (string-match-p "kind=discipline status=parse-failed" (buffer-string)))
          (should (string-match-p "reason=\\\"Could not parse discipline page\\\"" (buffer-string))))))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

(ert-deftest jupiterweb-test-refresh-curriculum-logs-success ()
  "Test curriculum refresh logs a final success message and cache file."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-refresh-curriculum/")
        (messages nil))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages)))
              ((symbol-function 'jupiterweb-fetch-curriculum-html)
               (lambda ()
                 "<tr><td><a href=\"obterDisciplina?sgldis=4300157&codcur=43031&codhab=0\">4300157</a></td><td>Ciência, Educação e Linguagem</td></tr>")))
      (let ((curriculum (jupiterweb-refresh-curriculum-cache)))
        (should (= (length (plist-get curriculum :disciplines)) 1))
        (should (member "JupiterWeb: 🟩 Curriculum loaded successfully: 1 disciplines cached."
                        messages))
        (should (file-exists-p (jupiterweb--cache-file-curriculum)))
        (with-temp-buffer
          (insert-file-contents (jupiterweb--log-file))
          (should (string-match-p "kind=curriculum status=success" (buffer-string)))
          (should (string-match-p "disciplines=1" (buffer-string))))))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

(ert-deftest jupiterweb-test-refresh-curriculum-logs-not-found ()
  "Test curriculum refresh logs no-link parse failures."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-refresh-curriculum-empty/")
        (messages nil))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (push (apply #'format fmt args) messages)))
              ((symbol-function 'jupiterweb-fetch-curriculum-html)
               (lambda () "<html>No grade links</html>")))
      (let ((curriculum (jupiterweb-refresh-curriculum-cache)))
        (should (null (plist-get curriculum :disciplines)))
        (should (member "JupiterWeb: 🔴 Curriculum load failed: no discipline links found."
                        messages))
        (with-temp-buffer
          (insert-file-contents (jupiterweb--log-file))
          (should (string-match-p "kind=curriculum status=not-found" (buffer-string)))
          (should (string-match-p "reason=\\\"no discipline links found\\\"" (buffer-string))))))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

;;; Format helpers

(ert-deftest jupiterweb-test-format-name-code ()
  "Test format-name-code returns exact expected string."
  (should (equal (jupiterweb--format-name-code
                  (list :name "Fundamentos de Mecanica" :sgldis "4300151"))
                 "Fundamentos de Mecanica (4300151)")))

(ert-deftest jupiterweb-test-format-code-name ()
  "Test format-code-name returns exact expected string."
  (should (equal (jupiterweb--format-code-name
                  (list :name "Fundamentos de Mecanica" :sgldis "4300151"))
                 "4300151 - Fundamentos de Mecanica")))

(ert-deftest jupiterweb-test-display-record-fills-missing-name-from-cache ()
  "Test display record enrichment when curriculum name is missing or equals code."
  (cl-letf (((symbol-function 'jupiterweb--ensure-discipline)
             (lambda (_sgldis)
               (list :sgldis "4300151" :name "Fundamentos de Mecanica" :name-en "Mechanics"))))
    (let ((record (jupiterweb--discipline-display-record
                   (list :sgldis "4300151" :name "4300151"))))
      (should (equal (plist-get record :name) "Fundamentos de Mecanica"))
      (should (equal (jupiterweb--format-name-code record)
                     "Fundamentos de Mecanica (4300151)"))
      (should (equal (jupiterweb--format-code-name record)
                     "4300151 - Fundamentos de Mecanica")))))

(ert-deftest jupiterweb-test-selection-and-insertion-use-parsed-discipline-name ()
  "Test selection and insertion use the name cell from the curriculum table."
  (let ((jupiterweb-cache-fetch-policy 'manual))
    (setq jupiterweb--curriculum-memory
          (list :disciplines
                (jupiterweb-parse-curriculum
                 "<tr><td><a href=\"obterDisciplina?sgldis=4300157&codcur=43031&codhab=0\" class=\"link_gray\"> 4300157</a></td><td> Ciência, Educação e Linguagem</td></tr>")))
    (let* ((candidates (jupiterweb--build-candidates))
           (candidate (caar candidates)))
      (should (equal candidate "Ciência, Educação e Linguagem (4300157)"))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _args) candidate)))
        (with-temp-buffer
          (jupiterweb-insert-name-code)
          (should (equal (buffer-string)
                         "Ciência, Educação e Linguagem (4300157)")))
        (with-temp-buffer
          (jupiterweb-insert-code-name)
          (should (equal (buffer-string)
                         "4300157 - Ciência, Educação e Linguagem")))))))

;;; Retry helper

(ert-deftest jupiterweb-test-retry-helper ()
  "Test that retry helper retries failing thunks up to jupiterweb-retries."
  (let ((jupiterweb-retries 3)
        (attempts 0))
    (should (equal
             (jupiterweb--with-retries
              (lambda ()
                (setq attempts (1+ attempts))
                (when (> attempts 2)
                  "success")))
             "success"))
    (should (equal attempts 3)))
  (let ((jupiterweb-retries 2))
    (should-error
     (jupiterweb--with-retries
      (lambda () (error "always fails"))
      2))))

;;; Decode response

(ert-deftest jupiterweb-test-decode-response-cp1252 ()
  "Test that decode-response handles CP1252 bytes."
  (let ((decoded (jupiterweb--decode-response "hello")))
    (should (stringp decoded))
    (should (string-prefix-p "hello" decoded))))

;;; Provisional XXX code

(ert-deftest jupiterweb-test-provisional-xxx-code ()
  "Test that XXX codes produce fallback records without network."
  (let ((fallback (jupiterweb--build-syllabus-fallback "XXX001")))
    (should (equal (plist-get fallback :sgldis) "XXX001"))
    (should (equal (plist-get fallback :syllabus-status) "fallback"))))

;;; Memory cache

(ert-deftest jupiterweb-test-memory-cache ()
  "Test that memory cache stores and clears data."
  (setq jupiterweb--curriculum-memory '(:test data))
  (should (equal jupiterweb--curriculum-memory '(:test data)))
  (jupiterweb-cache-clear-memory)
  (should (null jupiterweb--curriculum-memory))
  (should (null jupiterweb--discipline-memory)))

(ert-deftest jupiterweb-test-transient-loads-suffix-commands ()
  "Test that requiring transient module defines referenced suffix commands."
  (require 'jupiterweb-transient)
  (should (fboundp 'jupiterweb-dispatch))
  (should (commandp 'jupiterweb-cache-clear-memory))
  (should (commandp 'jupiterweb-cache-clear-disk))
  (should (commandp 'jupiterweb-export-cache-json))
  (should (commandp 'jupiterweb-select-discipline)))

(ert-deftest jupiterweb-test-byte-compile-entrypoint-with-transient ()
  "Test byte-compiling the transient module and entry point does not void jupiterweb-dispatch."
  (let ((default-directory (file-name-directory (locate-library "jupiterweb.el"))))
    (dolist (file '("jupiterweb-transient.elc" "jupiterweb.elc"))
      (when (file-exists-p file)
        (delete-file file)))
    (unwind-protect
        (let ((byte-compile-error-on-warn nil))
          (should (byte-compile-file "jupiterweb-transient.el"))
          (should (byte-compile-file "jupiterweb.el")))
      (dolist (file '("jupiterweb-transient.elc" "jupiterweb.elc"))
        (when (file-exists-p file)
          (delete-file file))))))

(ert-deftest jupiterweb-test-export-json-disciplines-is-array ()
  "Test that exported JSON encodes disciplines as an array, not an object."
  (let ((jupiterweb-cache-directory "/tmp/test-jupiterweb-export/"))
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))
    (setq jupiterweb--curriculum-memory
          (list :course-key "43-43031-0-N"
                :disciplines (list (list :sgldis "4300151"
                                         :name "Test Discipline"))))
    (let ((file "/tmp/test-jupiterweb-export/out.json"))
      (jupiterweb-export-cache-json file nil)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let* ((json-object-type 'plist)
               (json-array-type 'list)
               (json-key-type 'keyword)
               (data (json-read)))
          (should (listp (plist-get data :disciplines)))
          (should (equal (plist-get (car (plist-get data :disciplines)) :sgldis)
                         "4300151")))))
    (jupiterweb-cache-clear-memory)
    (when (file-directory-p jupiterweb-cache-directory)
      (delete-directory jupiterweb-cache-directory t))))

(provide 'jupiterweb-test)
;;; jupiterweb-test.el ends here