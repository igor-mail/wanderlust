;;; wl-qs.el --- Prompt for a query string and display search results.

;; Copyright (C) 2014-2015 Erik Hetzner <egh@e6h.org>

;; Author: Erik Hetzner <egh@e6h.org>
;; Keywords: mail, net news

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;;; Code:

(require 'elmo-imap4)
(require 'elmo-search)
(require 'wl-folder)
(require 'wl-summary)
(require 'wl-util)

(defcustom wl-quicksearch-folder
  nil
  "Folder to use for wl-quicksearch search.

To use an external search program, speficy a search folder, e.g.
\"[]\".  To define a search target to pass for the grep engine,
use \"[]~/Mail/inbox\".  To use a different search engine, use e.g.
\"[]!grep\".

To use Gmail's raw search, use a gmail folder, e.g.
\"%[Gmail]/All Mail:USERNAME@imap.gmail.com\".

Any other type of folder will be searched using a filter folder."
  :group 'wl-quicksearch
  :type '(string))

;; Needed for Gmail search.
(add-to-list 'elmo-imap4-search-keys "x-gm-raw")

(luna-define-generic wl-quicksearch-goto-search-folder (base-folder)
  "Prompt for a query and jump to the quicksearch folder for BASE-FOLDER.")

(luna-define-method wl-quicksearch-goto-search-folder ((base-folder elmo-search-folder))
  "Prompt for a search condition and jump to a new search folder.

Folder is the same BASE-FOLDER but with a new search pattern."
  (let* ((engine (elmo-search-folder-engine-internal base-folder))
         (base-folder-name (elmo-folder-name-internal base-folder))
         (engine-type (or (and (string-match "!\\(.*\\)$" base-folder-name)
                               (match-string 1 base-folder-name))
                          elmo-search-default-engine))
         (q (wl-quicksearch-escape-query-string
             (read-string (format "%s query: " engine-type)))))
    (wl-folder-goto-folder-subr
     (format (format "[\"%s\"]%s!%s" q
                     (elmo-search-engine-param-internal engine)
                     engine-type)))))

(defun wl-quicksearch-escape-query-string (str)
  "Replace single quotes (') in STR with double quotes (\"), then escape double-quotes."
  (let* ((str1 (elmo-replace-in-string str "'" "\"" t))
         (str2 (elmo-replace-in-string str1 "\"" "\\\"" t)))
    str2))

(luna-define-method wl-quicksearch-goto-search-folder ((base-folder elmo-folder))
  "Prompt for a search condition and jump to filter folder that searches BASE-FOLDER."
  (wl-folder-goto-folder-subr
   (concat "/"
           (wl-read-search-condition
            wl-fldmgr-make-filter-default)
           "/" (or (wl-quicksearch-get-archive-folder)
                   base-folder))))

(luna-define-method wl-quicksearch-goto-search-folder :around ((base-folder elmo-imap4-folder))
  "Jump to the quicksearch folder for BASE-FOLDER.

If BASE-FOLDER is a gmail.com folder, use raw gmail query.

Otherwise call parent method."
  (if (not (string-match "gmail.com$" (elmo-net-folder-server-internal base-folder)))
      (luna-call-next-method)
    (let* ((q (wl-quicksearch-escape-query-string
               (read-string "gmail query: "))))
      (wl-folder-goto-folder-subr
       (format "/x-gm-raw:\"%s\"/%s" q
               (elmo-folder-name-internal base-folder))))))

(defun wl-quicksearch-goto-search-folder-wrapper ()
  "Call `wl-quicksearch-goto-search-folder' on a folder built from `wl-quicksearch-folder'."
  (interactive)
  (if (null wl-quicksearch-folder)
      (error "The variable `wl-quicksearch-folder' is not set.  Please customize"))
  (wl-quicksearch-goto-search-folder
   (wl-folder-make-elmo-folder wl-quicksearch-folder)))

(define-key wl-folder-mode-map "'" 'wl-quicksearch-goto-search-folder-wrapper)
(define-key wl-summary-mode-map "'" 'wl-quicksearch-goto-search-folder-wrapper)

(define-key-after
  (lookup-key wl-folder-mode-map [menu-bar Folder])
  [quicksearch]
  '("Quick search" . wl-quicksearch-goto-search-folder-wrapper)
  (intern "Go to Draft Folder"))

(define-key-after
  (lookup-key wl-summary-mode-map [menu-bar Summary])
  [quicksearch]
  '("Quick search" . wl-quicksearch-goto-search-folder-wrapper)
  (intern "Go to other folder"))

(provide 'wl-qs)
;;; wl-qs.el ends here