;;; grammalecte.el --- Wrapper for Grammalecte -*- lexical-binding: t; -*-

;; Copyright (C) 2018 Étienne Deparis
;; Copyright (C) 2017 Guilhem Doulcier

;; Maintener: Étienne Deparis <etienne@depar.is>
;; Author: Guilhem Doulcier <guilhem.doulcier@espci.fr>
;;         Étienne Deparis <etienne@depar.is>
;; Created: 21 February 2017
;; Version: 1.5
;; Package-Requires: ((emacs "26.1"))
;; Keywords: i18n, text
;; Homepage: https://git.umaneti.net/flycheck-grammalecte/

;;; Commentary:

;; Adds support for Grammalecte (a french grammar checker) to GNU Emacs.

;;; License:

;; This file is not part of GNU Emacs.
;; However, it is distributed under the same license.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:

(require 'seq)

;;;; Configuration options:

(defgroup grammalecte nil
  "Grammalecte options"
  :group 'i18n)

(defconst grammalecte--site-directory (file-name-directory load-file-name)
  "Location of the grammalecte package.

This variable must point to the directory where the emacs-lisp and
python files named `grammalecte.el', `flycheck-grammalecte.el' and
`flycheck-grammalecte.py' are kept.  It must end with a / (see
`file-name-as-directory').

The default value is automatically computed from the included file.")

(defcustom grammalecte-python-package-directory
  (expand-file-name "grammalecte" grammalecte--site-directory)
  "Location of the Grammalecte python package.

This variable may be changed if you already have Grammalecte installed
somewhere on your machine.

This variable value must not end with a / (see `directory-file-name').

The default value is a folder alongside this elisp package."
  :type 'directory
  :package-version "1.5"
  :group 'grammalecte)

(defcustom grammalecte-download-without-asking nil
  "Download Grammalecte upstream package without asking if non-nil.

Otherwise, it will ask for a yes-or-no confirmation."
  :type 'boolean
  :package-version "1.5"
  :group 'grammalecte)

(defcustom grammalecte-check-upstream-timestamp nil
  "Timestamp of the last attempt to check upstream version of Grammalecte.

This timestamp must be a float, as returned by `float-time'."
  :type 'float
  :package-version "1.5"
  :group 'grammalecte)

(defcustom grammalecte-check-upstream-version-delay 10
  "Minimal delay in days before checking again upstream for a new release.

If this value is nil, 0 or negative, no check will never be attempt."
  :type 'integer
  :package-version "1.5"
  :group 'grammalecte)

(defvar grammalecte--debug-mode nil
  "Display some debug messages when non-nil.")



;;;; Grammalecte python package helper methods:

(defun grammalecte--augment-pythonpath-if-needed ()
  "Augment PYTHONPATH with the install directory of grammalecte.

If the parent directory of `grammalecte-python-package-directory'
is not this elisp package installation directory, then add the former in
the PYTHONPATH environment variable in order to make python scripts work
as expected."
  (let ((grammalecte-parent-path
         (file-name-directory
          (directory-file-name grammalecte-python-package-directory)))
        (current-pythonpath (or (getenv "PYTHONPATH") "")))
    (unless (or (string-match-p grammalecte-parent-path current-pythonpath)
                (string= grammalecte-parent-path grammalecte--site-directory))
      (setenv "PYTHONPATH"
              (if (string= current-pythonpath "")
                  grammalecte-parent-path
                (format "%s:%s" grammalecte-parent-path current-pythonpath))))))

(defun grammalecte--version ()
  "Return the currently installed Grammalecte version."
  (grammalecte--augment-pythonpath-if-needed)
  (let* ((python-script "from grammalecte.fr.gc_engine import __version__
print(__version__)")
         (fg-version
          (shell-command-to-string
           (format "python3 -c \"%s\"" python-script))))
    ;; Only return a version number if we got something which looks like a
    ;; version number (else it may be a python crash when Grammalecte is not
    ;; yet downloaded)
    (when (string-match "^[0-9.]+$" fg-version)
      (match-string 0 fg-version))))

(defun grammalecte--upstream-version ()
  "Return the upstream version of Grammalecte.

Signal a `file-error' error if something wrong happen while retrieving
the Grammalecte home page or if no version string is found in the page."
  (let ((url "https://grammalecte.net/index.html")
        (inhibit-message t)) ;; Do not display url-retrieve messages
    ;; Save the new version check timestamp
    (setq grammalecte-check-upstream-timestamp (float-time))
    (customize-save-variable 'grammalecte-check-upstream-timestamp
                             grammalecte-check-upstream-timestamp)
    (with-current-buffer (url-retrieve-synchronously url)
      (goto-char (point-min))
      (if (re-search-forward
           "<p id=\"version_num\">\\([0-9.]+\\)</p>"
           nil t) ;; Parse all downloaded data and avoid error
          (match-string 1)
        (signal 'file-error
                (list url "No version number found on grammalecte website"))))))

(defun grammalecte--download-zip (&optional grammalecte-version)
  "Download Grammalecte CLI zip file.

If given, this function will try to download the GRAMMALECTE-VERSION
of the python package."
  (let* ((up-version (if (or (not grammalecte-version)
                             (string= grammalecte-version "last"))
                         (grammalecte--upstream-version)
                       grammalecte-version))
         (zip-name (format "Grammalecte-fr-v%s.zip" up-version))
         (dl-url
          (format "https://grammalecte.net/grammalecte/zip/%s"
                  zip-name))
         (zip-file (expand-file-name
                    zip-name
                    grammalecte--site-directory)))
    ;; Do not download it twice if it's still there for some reason...
    (unless (file-exists-p zip-file)
      (url-copy-file dl-url zip-file)
      (message "[Grammalecte] Downloaded to %s" zip-file))
    zip-file))

(defun grammalecte--extract-zip (zip-file)
  "Extract ZIP-FILE."
  (let ((extracted-folder (file-name-sans-extension zip-file)))
    ;; Unzip file given in parameters in `extracted-folder'.
    (call-process "unzip" nil nil nil
                  zip-file (concat "-d" extracted-folder))
    ;; Remove the zip file
    (delete-file zip-file)
    (message "[Grammalecte] Extracted to %s" extracted-folder)
    extracted-folder))

(defun grammalecte--install-py-files (extracted-folder)
  "Install the interesting files from EXTRACTED-FOLDER.

Move the `grammalecte' subfolder, containing the necessary python files
from EXTRACTED-FOLDER to their destination, alongside the other
package files."
  (let ((source-folder
         (expand-file-name "grammalecte" extracted-folder))
        (target-folder grammalecte-python-package-directory))
    ;; Always do a clean update. Begin by removing old folder if it's
    ;; present.
    (when (file-directory-p target-folder)
      (delete-directory target-folder t))
    ;; Extract the `grammalecte' subfolder from the extracted directory.
    (when (file-exists-p source-folder)
      (rename-file source-folder target-folder)
      ;; Do some cleanup
      (delete-directory extracted-folder t))
    (message "[Grammalecte] Installed in %s" target-folder)
    target-folder))

(defun grammalecte--download-grammalecte-if-needed ()
  "Install Grammalecte python package if it's required.

This function will only run if
`grammalecte-check-upstream-version-delay' is non-nil
and greater than 0.

If `grammalecte-check-upstream-timestamp' is nil, the
function will run, no matter the above delay value (as soon as it
is not nil or 0).  Otherwise, it will only run if there is more
than `grammalecte-check-upstream-version-delay' days
since the value of
`grammalecte-check-upstream-timestamp'."
  (when (and (integerp grammalecte-check-upstream-version-delay)
             (> 0 grammalecte-check-upstream-version-delay)
             (or (not grammalecte-check-upstream-timestamp)
                 (> (- (float-time) grammalecte-check-upstream-timestamp)
                    (* 86400 grammalecte-check-upstream-version-delay))))
    (let ((local-version (grammalecte--version))
          (upstream-version (grammalecte--upstream-version)))
      (when (stringp upstream-version)
        (if (stringp local-version)
            ;; It seems we have a local version of grammalecte.
            ;; Compare it with upstream
            (when (and (string-version-lessp local-version upstream-version)
                       (or grammalecte-download-without-asking
                           (yes-or-no-p
                            "[Grammalecte] Grammalecte is out of date.  Download it NOW?")))
              (grammalecte-download-grammalecte upstream-version))
          ;; It seems there is no currently downloaded Grammalecte
          ;; package. Force install it, as nothing will work without it.
          (grammalecte-download-grammalecte upstream-version))))))

;;;###autoload
(defun grammalecte-download-grammalecte (grammalecte-version)
  "Download, extract and install Grammalecte python program.

This function will try to download the GRAMMALECTE-VERSION of the python
package.  If GRAMMALECTE-VERSION is \"last\", the last version of the package
will be downloaded.

This function can also be used at any time to upgrade the Grammalecte python
program."
  (interactive "sVersion: ")
  (grammalecte--install-py-files
   (grammalecte--extract-zip
    (grammalecte--download-zip grammalecte-version))))



;;;; Definition helper methods:

(declare-function nxml-forward-element "nxml-mode")

(defun grammalecte--extract-cnrtl-definition (start)
  "Extract a definition from the current XML buffer at START."
  (require 'nxml-mode)
  (goto-char start)
  (delete-region (point-min) (point))
  (let ((inhibit-message t)) ;; Silences nxml-mode messages
    (nxml-mode)
    (nxml-forward-element)
    (delete-region (point) (point-max))
    (libxml-parse-html-region (point-min) (point-max))))

(defun grammalecte--fetch-cnrtl-word (word)
  "Fetch WORD definition, according to TLFi, on CNRTL."
  (let ((url (format "https://www.cnrtl.fr/definition/%s" word))
        (definitions '()) count start)
    ;; Get initial definitions location, number of definitions and
    ;; initial definition.
    (with-current-buffer (url-retrieve-synchronously url t t)
      (goto-char (point-min))
      (if (search-forward "<div id=\"lexicontent\">" nil t)
          (setq start (match-beginning 0))
        (when grammalecte--debug-mode
          (display-warning 'grammalecte "Définition non trouvée.")))
      (if (re-search-backward "'/definition/[^/]+//\\([0-9]+\\)'" nil t)
          (setq count (string-to-number (match-string 1)))
        (when grammalecte--debug-mode
          (display-warning 'grammalecte "Nombre de définitions non trouvé.")))
      (when (and start count)
        (push (grammalecte--extract-cnrtl-definition start) definitions)
        (kill-buffer (current-buffer))))
    ;; Collect additional definitions.
    (when (and start count)
      (dotimes (i count)
        (with-current-buffer
            (url-retrieve-synchronously (format "%s/%d" url (1+ i)) t t)
          (push (grammalecte--extract-cnrtl-definition start) definitions)
          (kill-buffer (current-buffer)))))
    (reverse definitions)))



;;;; Synonyms and antonyms helper methods:

(defun grammalecte--extract-crisco-words (type)
  "Extract all words for TYPE from the current buffer."
  (save-excursion
    (save-restriction
      (let ((results '()) content start end)
        (goto-char (point-min))
        (if (re-search-forward
             (format "<i class=[^>]*>[[:digit:]]* %s?" type)
             nil t)
            (setq start (match-beginning 0))
          (when grammalecte--debug-mode
            (display-warning
             'grammalecte
             (format "Début de liste des %s non trouvée." type))))
        (if (re-search-forward
             (format "<!-- ?Fin liste des %s ?-->" type)
             nil t)
            (setq end (match-beginning 0))
          (when grammalecte--debug-mode
            (display-warning
             'grammalecte
             (format "Fin de liste des %s non trouvée." type))))
        (when (and start end)
          (narrow-to-region start end)
          (setq content (decode-coding-string (buffer-string) 'utf-8-unix))
          (with-temp-buffer
            (insert content)
            (goto-char (point-min))
            (while (re-search-forward "[[:blank:]]*<a href=\"/des/synonymes/[^\"]*\">\\([^<]*\\)</a>,?" nil t)
              (push (match-string 1) results))))
        results))))

(defun grammalecte--fetch-crisco-words (word)
  "Fetch synonymes and antonymes for the given WORD from the CRISCO."
  (let ((url (format "https://crisco2.unicaen.fr/des/synonymes/%s" word))
        found-words)
    (with-current-buffer (url-retrieve-synchronously url t t)
      (let ((synonymes (grammalecte--extract-crisco-words "synonymes"))
            (antonymes (grammalecte--extract-crisco-words "antonymes")))
        (setq found-words (list :synonymes synonymes
                                :antonymes antonymes))
        (if (and grammalecte--debug-mode
                 (seq-empty-p synonymes) (seq-empty-p antonymes))
            (pop-to-buffer (current-buffer))
          (kill-buffer (current-buffer)))))
    found-words))

(defun grammalecte--propertize-crisco-words (words)
  "Insert WORDS at point, after having propertized them."
  (if (seq-empty-p words)
      (insert "Aucun résultat")
    (insert
     (mapconcat
      #'(lambda (w)
          (concat "- "
                  (propertize w 'mouse-face 'highlight
                                'help-echo "mouse-1: Remplacer par…")))
      words "\n"))))

(defvar-local grammalecte-looked-up-type nil
  "What kind of word was looked up by the user to open the current buffer.

Can be either `synonyms', `conjugate', or `define'.  When non-nil, the
corresponding looked-up word must be available in
`grammalecte-looked-up-word'.")

(defvar-local grammalecte-looked-up-word nil
  "The word currently consulted by the user in the current buffer.")



;;;; Special buffer major mode methods

(defun grammalecte--kill-ring-save-at-point (&optional pos replace)
  "Copy the word at point or POS and paste it when REPLACE is non-nil.

The word is taken from the synonyms result buffer at point or POS when
POS is non-nil.

When REPLACE is non-nil, it will replace the word at point in the
other buffer by the copied word."
  (unless pos (setq pos (point)))
  (goto-char pos)
  (when (string= "-" (string (char-after (line-beginning-position))))
    (let ((beg (+ 2 (line-beginning-position))) ;; ignore the leading -
          (end (line-end-position)))
      (kill-ring-save beg end)
      (if (not replace)
          (message
           "%s sauvé dans le kill-ring.  Utilisez `C-y' n'importe où pour l'utiliser."
           (buffer-substring-no-properties beg end))
        (quit-window t)
        (grammalecte--delete-word-at-point)
        (yank)))))

(defun grammalecte--delete-word-at-point ()
  "Delete the word around point, or region if one is active."
  (let ((bounds (if (use-region-p)
                    (cons (region-beginning) (region-end))
                  (bounds-of-thing-at-point 'word))))
    (when bounds
      (delete-region (car bounds) (cdr bounds)))))

(defun grammalecte--propertize-conjugation-buffer ()
  "Propertize some important words in the conjugation buffer."
  (goto-char (point-min))
  (while (re-search-forward "^\\* [^\n]+$" nil t)
    (replace-match (propertize (match-string 0) 'face 'org-level-1)))
  (goto-char (point-min))
  (while (re-search-forward "^\\*\\* [^\n]+$" nil t)
    (replace-match (propertize (match-string 0) 'face 'org-level-2)))
  (goto-char (point-min))
  (while (re-search-forward "\\*\\(?:avoir\\|être\\)\\*" nil t)
    (replace-match (propertize (match-string 0) 'face 'bold)))
  (goto-char (point-min))
  (while (re-search-forward "^\\- \\([^ \n]+\\)$" nil t)
    (replace-match
     (propertize (match-string 1) 'mouse-face 'highlight
                 'help-echo "mouse-1: Remplacer par…")
     t t nil 1)))

(defun grammalecte--revert-synonyms (word)
  "Revert current buffer with the found synonyms for WORD."
  (let ((buffer-read-only nil)
        (found-words (grammalecte--fetch-crisco-words word)))
    (erase-buffer)
    (setq grammalecte-looked-up-type 'synonym
          grammalecte-looked-up-word word)
    (insert (propertize (format "* Synonymes de %s" word)
                        'face 'org-level-1) "\n\n")
    (grammalecte--propertize-crisco-words
     (plist-get found-words :synonymes))
    (insert "\n\n" (propertize (format "* Antonymes de %s" word)
                               'face 'org-level-1) "\n\n")
    (grammalecte--propertize-crisco-words
     (plist-get found-words :antonymes))
    (insert "\n"))) ;; Avoid ugly last button

(defun grammalecte--revert-conjugate (verb)
  "Revert current buffer with the found conjugation for VERB."
  (let ((buffer-read-only nil))
    (erase-buffer)
    (setq grammalecte-looked-up-type 'conjugate
          grammalecte-looked-up-word verb)
    (grammalecte--download-grammalecte-if-needed)
    (grammalecte--augment-pythonpath-if-needed)
    (insert
     (shell-command-to-string
      (format "python3 %s %s"
              (expand-file-name "conjugueur.py" grammalecte--site-directory)
              verb)))
    (grammalecte--propertize-conjugation-buffer)))

(defun grammalecte--revert-define (word)
  "Revert current buffer with the found definitions for WORD."
  (let ((buffer-read-only nil)
        (definitions (grammalecte--fetch-cnrtl-word word)))
    (erase-buffer)
    (setq grammalecte-looked-up-type 'define
          grammalecte-looked-up-word word)
    (if (seq-empty-p definitions)
        (insert (format "Aucun résultat pour %s." word))
      (dolist (d definitions)
        (shr-insert-document d)
        (insert "\n\n\n")))))

(defun grammalecte--revert-buffer (&optional _ignore-auto _noconfirm)
  "Replace the current buffer content by an up-to-date one.

Replace it either by a refreshed list of synonyms or conjugation table."
  ;; We are working on a read only buffer, thus deactivate it first
  (when grammalecte-looked-up-word
    (let ((revert-func
           (intern
            (concat "grammalecte--revert-"
                    (symbol-name grammalecte-looked-up-type)))))
      (when (fboundp revert-func)
        (funcall revert-func grammalecte-looked-up-word)))))

(defun grammalecte--set-buffer-title (title)
  "Decorate the current buffer `header-line-format', prefixed by TITLE.

It adds information on how to close it."
  (setq-local
   header-line-format
   (format-message
    "%s. Quitter `q' ou `k', Copier avec `w'. Remplacer avec `mouse-1' ou `RET'."
    title)))

(defun grammalecte-kill-ring-save ()
  "Save word at point in `kill-ring'."
  (interactive)
  (grammalecte--kill-ring-save-at-point))

(defun grammalecte-mouse-save-and-replace (event)
  "Replace word by the one focused by EVENT mouse click.

The word is not removed from the `kill-ring'."
  (interactive "e")
  (grammalecte--kill-ring-save-at-point
   (posn-point (event-end event)) t))

(defun grammalecte-save-and-replace ()
  "Replace word in other buffer by the one at point.

The word is not removed from the `kill-ring'."
  (interactive)
  (grammalecte--kill-ring-save-at-point (point) t))

(defvar grammalecte-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "o" #'other-window)
    (define-key map "w" #'grammalecte-kill-ring-save)
    (define-key map (kbd "<mouse-1>")
      #'grammalecte-mouse-save-and-replace)
    (define-key map (kbd "<RET>") #'grammalecte-save-and-replace)
    map)
  "Keymap for `grammalecte-mode'.")

(define-derived-mode grammalecte-mode special-mode
  "Grammalecte mode"
  "Major mode used to display results of a synonym research or
conjugation table.
The buffer is read-only.
Type o to go back to your previous buffer.
Type \\[grammalecte-kill-ring-save] to copy word at point in the
  grammalecte buffer in the `kill-ring' (and let you do whatever you
  want with it after).
Type \\[grammalecte-save-and-replace] to replace the word at point in
  the buffer you came from by the one at point in the grammalecte
  buffer.  The word is not removed from the `kill-ring'.
Click \\[grammalecte-mouse-save-and-replace] to replace the word at
  point in the buffer you came from by the one you just click in the
  grammalecte buffer.  The word is not removed from the `kill-ring'."
  (buffer-disable-undo)
  (setq show-trailing-whitespace nil
        revert-buffer-function #'grammalecte--revert-buffer)
  (when (bound-and-true-p global-linum-mode)
    (linum-mode -1))
  (when (and (fboundp 'nlinum-mode)
             (bound-and-true-p global-nlinum-mode))
    (nlinum-mode -1))
  (when (and (fboundp 'display-line-numbers-mode)
             (bound-and-true-p global-display-line-numbers-mode))
    (display-line-numbers-mode -1)))



;;;; Definition public methods:

;;;###autoload
(defun grammalecte-define (word)
  "Find definition for the french WORD.

This function will fetch data from the CNRTL¹ website, in the TLFi².

The found words are then displayed in a new buffer in another window.

See URL `https://www.cnrtl.fr/definition/'.

¹ « Centre National de Ressources Textuelles et Lexicales »
² « Trésor de la Langue Française informatisé »."
  (interactive "sMot: ")
  (pop-to-buffer (get-buffer-create (format "*Définition de %s*" word)))
  (setq header-line-format (format-message "Définition de %s." word))
  (special-mode)
  (visual-line-mode)
  (grammalecte--revert-define word)
  (goto-char (point-min)))


;;;###autoload
(defun grammalecte-define-at-point ()
  "Find definitions for the french word at point."
  (interactive)
  (let ((word (thing-at-point 'word 'no-properties)))
    (if word
        (grammalecte-define word)
      (call-interactively 'grammalecte-define))))



;;;; Synonyms and antonyms public methods:

;;;###autoload
(defun grammalecte-find-synonyms (word)
  "Find french synonyms and antonyms for the given WORD.

This function will fetch data from the CRISCO¹ thesaurus.

The found words are then displayed in a new buffer in another window.

¹ See URL `https://crisco2.unicaen.fr/des/synonymes/'"
  (interactive "sMot: ")
  (pop-to-buffer (get-buffer-create (format "*Synonymes de %s*" word)))
  (grammalecte--set-buffer-title
   "Sélection de synonymes ou d'antonymes.")
  (grammalecte-mode)
  (grammalecte--revert-synonyms word)
  (goto-char (point-min)))

;;;###autoload
(defun grammalecte-find-synonyms-at-point ()
  "Find french synonyms and antonyms for the word at point."
  (interactive)
  (let ((word (thing-at-point 'word 'no-properties)))
    (if word
        (grammalecte-find-synonyms word)
      (call-interactively 'grammalecte-find-synonyms))))



;;;; Conjugate public methods:

;;;###autoload
(defun grammalecte-conjugate-verb (verb)
  "Display the conjugation table for the given VERB."
  (interactive "sVerbe: ")
  (pop-to-buffer (get-buffer-create (format "*Conjugaison de %s*" verb)))
  (grammalecte--set-buffer-title (format "Conjugaison de %s." verb))
  (grammalecte-mode)
  (grammalecte--revert-conjugate verb)
  (goto-char (point-min)))


(provide 'grammalecte)
;;; grammalecte.el ends here
