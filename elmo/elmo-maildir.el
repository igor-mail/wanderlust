;;; elmo-maildir.el --- Maildir interface for ELMO.

;; Copyright (C) 1998,1999,2000 Yuuichi Teranishi <teranisi@gohome.org>

;; Author: Yuuichi Teranishi <teranisi@gohome.org>
;; Keywords: mail, net news

;; This file is part of ELMO (Elisp Library for Message Orchestration).

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
;;

;;; Commentary:
;;

;;; Code:
;;

(eval-when-compile (require 'cl))

(require 'elmo-util)
(require 'elmo)
(require 'elmo-map)

(defcustom elmo-maildir-folder-path "~/Maildir"
  "*Maildir folder path."
  :type 'directory
  :group 'elmo)

(defconst elmo-maildir-flag-specs '((important ?F)
				    (read ?S)
				    (unread ?S 'remove)
				    (answered ?R)))

;;; ELMO Maildir folder
(eval-and-compile
  (luna-define-class elmo-maildir-folder
		     (elmo-map-folder)
		     (directory unread-locations
				flagged-locations
				answered-locations))
  (luna-define-internal-accessors 'elmo-maildir-folder))

(luna-define-method elmo-folder-initialize ((folder
					     elmo-maildir-folder)
					    name)
  (if (file-name-absolute-p name)
      (elmo-maildir-folder-set-directory-internal
       folder
       (expand-file-name name))
    (elmo-maildir-folder-set-directory-internal
     folder
     (expand-file-name
      name
      elmo-maildir-folder-path)))
  folder)

(luna-define-method elmo-folder-expand-msgdb-path ((folder
						    elmo-maildir-folder))
  (expand-file-name
   (elmo-replace-string-as-filename
    (elmo-maildir-folder-directory-internal folder))
   (expand-file-name
    "maildir"
    elmo-msgdb-directory)))

(defun elmo-maildir-message-file-name (folder location)
  "Get a file name of the message from FOLDER which corresponded to
LOCATION."
  (let ((file (file-name-completion
	       location
	       (expand-file-name
		"cur"
		(elmo-maildir-folder-directory-internal folder)))))
    (if file
	(expand-file-name
	 (if (eq file t) location file)
	 (expand-file-name
	  "cur"
	  (elmo-maildir-folder-directory-internal folder))))))

(defsubst elmo-maildir-list-location (dir &optional child-dir)
  (let* ((cur-dir (expand-file-name (or child-dir "cur") dir))
	 (cur (directory-files cur-dir
			       nil "^[^.].*$" t))
	 unread-locations flagged-locations answered-locations
	 sym locations flag-list)
    (setq locations
	  (mapcar
	   (lambda (x)
	     (if (string-match "^\\([^:]+\\):\\([^:]+\\)$" x)
		 (progn
		   (setq sym (elmo-match-string 1 x)
			 flag-list (string-to-char-list
				    (elmo-match-string 2 x)))
		   (when (memq ?F flag-list)
		     (setq flagged-locations
			   (cons sym flagged-locations)))
		   (when (memq ?R flag-list)
		     (setq answered-locations
			   (cons sym answered-locations)))
		   (unless (memq ?S flag-list)
		     (setq unread-locations
			   (cons sym unread-locations)))
		   sym)
	       x))
	   cur))
    (list locations unread-locations flagged-locations answered-locations)))

(luna-define-method elmo-map-folder-list-message-locations
  ((folder elmo-maildir-folder))
  (elmo-maildir-update-current folder)
  (let ((locs (elmo-maildir-list-location
	       (elmo-maildir-folder-directory-internal folder))))
    ;; 0: locations, 1: unread-locs, 2: flagged-locs 3: answered-locs
    (elmo-maildir-folder-set-unread-locations-internal folder (nth 1 locs))
    (elmo-maildir-folder-set-flagged-locations-internal folder (nth 2 locs))
    (elmo-maildir-folder-set-answered-locations-internal folder (nth 3 locs))
    (nth 0 locs)))

(luna-define-method elmo-map-folder-list-flagged ((folder elmo-maildir-folder)
						  flag)
  (case flag
    (unread
     (elmo-maildir-folder-unread-locations-internal folder))
    (important
     (elmo-maildir-folder-flagged-locations-internal folder))
    (answered
     (elmo-maildir-folder-answered-locations-internal folder))
    (otherwise
     t)))

(luna-define-method elmo-folder-msgdb-create ((folder elmo-maildir-folder)
					      numbers flag-table)
  (let* ((unread-list (elmo-maildir-folder-unread-locations-internal folder))
	 (flagged-list (elmo-maildir-folder-flagged-locations-internal folder))
	 (answered-list (elmo-maildir-folder-answered-locations-internal
			 folder))
	 (len (length numbers))
	 (new-msgdb (elmo-make-msgdb))
	 (i 0)
	 entity message-id flags location)
    (message "Creating msgdb...")
    (dolist (number numbers)
      (setq location (elmo-map-message-location folder number))
      (setq entity
	    (elmo-msgdb-create-message-entity-from-file
	     (elmo-msgdb-message-entity-handler new-msgdb)
	     number
	     (elmo-maildir-message-file-name folder location)))
      (when entity
	(setq message-id (elmo-message-entity-field entity 'message-id)
	      ;; Precede flag-table to file-info.
	      flags (copy-sequence
		     (elmo-flag-table-get flag-table message-id)))

	;; Already flagged on filename (precede it to flag-table).
	(when (member location flagged-list)
	  (or (memq 'important flags)
	      (setq flags (cons 'important flags))))
	(when (member location answered-list)
	  (or (memq 'answered flags)
	      (setq flags (cons 'answered flags))))
	(unless (member location unread-list)
	  (and (memq 'unread flags)
	       (setq flags (delq 'unread flags))))

	;; Update filename's info portion according to the flag-table.
	(when (and (memq 'important flags)
		   (not (member location flagged-list)))
	  (elmo-maildir-set-mark
	   (elmo-maildir-message-file-name folder location)
	   ?F)
	  ;; Append to flagged location list.
	  (elmo-maildir-folder-set-flagged-locations-internal
	   folder
	   (cons location
		 (elmo-maildir-folder-flagged-locations-internal
		  folder)))
	  (setq flags (delq 'unread flags)))
	(when (and (memq 'answered flags)
		   (not (member location answered-list)))
	  (elmo-maildir-set-mark
	   (elmo-maildir-message-file-name folder location)
	   ?R)
	  ;; Append to answered location list.
	  (elmo-maildir-folder-set-answered-locations-internal
	   folder
	   (cons location
		 (elmo-maildir-folder-answered-locations-internal folder)))
	  (setq flags (delq 'unread flags)))
	(when (and (not (memq 'unread flags))
		   (member location unread-list))
	  (elmo-maildir-set-mark
	   (elmo-maildir-message-file-name folder location)
	   ?S)
	  ;; Delete from unread locations.
	  (elmo-maildir-folder-set-unread-locations-internal
	   folder
	   (delete location
		   (elmo-maildir-folder-unread-locations-internal
		    folder))))
	(unless (memq 'unread flags)
	  (setq flags (delq 'new flags)))
	(elmo-global-flags-set flags folder number message-id)
	(elmo-msgdb-append-entity new-msgdb entity flags)
	(when (> len elmo-display-progress-threshold)
	  (setq i (1+ i))
	  (elmo-display-progress
	   'elmo-maildir-msgdb-create "Creating msgdb..."
	   (/ (* i 100) len)))))
    (message "Creating msgdb...done")
    (elmo-msgdb-sort-by-date new-msgdb)))

(defun elmo-maildir-cleanup-temporal (dir)
  ;; Delete files in the tmp dir which are not accessed
  ;; for more than 36 hours.
  (let ((cur-time (current-time))
	(count 0)
	last-accessed)
    (mapcar (function
	     (lambda (file)
	       (setq last-accessed (nth 4 (file-attributes file)))
	       (when (or (> (- (car cur-time)(car last-accessed)) 1)
			 (and (eq (- (car cur-time)(car last-accessed)) 1)
			      (> (- (cadr cur-time)(cadr last-accessed))
				 64064))) ; 36 hours.
		 (message "Maildir: %d tmp file(s) are cleared."
			  (setq count (1+ count)))
		 (delete-file file))))
	    (directory-files (expand-file-name "tmp" dir)
			     t ; full
			     "^[^.].*$" t))))

(defun elmo-maildir-update-current (folder)
  "Move all new msgs to cur in the maildir."
  (let* ((maildir (elmo-maildir-folder-directory-internal folder))
	 (news (directory-files (expand-file-name "new"
						  maildir)
				nil
				"^[^.].*$" t)))
    ;; cleanup tmp directory.
    (elmo-maildir-cleanup-temporal maildir)
    ;; move new msgs to cur directory.
    (while news
      (rename-file
       (expand-file-name (car news) (expand-file-name "new" maildir))
       (expand-file-name (concat
			  (car news)
			  (unless (string-match ":2,[A-Z]*$" (car news))
			    ":2,"))
			 (expand-file-name "cur" maildir)))
      (setq news (cdr news)))))

(defun elmo-maildir-set-mark (filename mark)
  "Mark the FILENAME file in the maildir.  MARK is a character."
  (if (string-match "^\\([^:]+:[12],\\)\\(.*\\)$" filename)
      (let ((flaglist (string-to-char-list (elmo-match-string
					    2 filename))))
	(unless (memq mark flaglist)
	  (setq flaglist (sort (cons mark flaglist) '<))
	  (rename-file filename
		       (concat (elmo-match-string 1 filename)
			       (char-list-to-string flaglist)))))
    ;; Rescue no info file in maildir.
    (rename-file filename
		 (concat filename ":2," (char-to-string mark))))
  t)

(defun elmo-maildir-delete-mark (filename mark)
  "Mark the FILENAME file in the maildir.  MARK is a character."
  (if (string-match "^\\([^:]+:2,\\)\\(.*\\)$" filename)
      (let ((flaglist (string-to-char-list (elmo-match-string
					    2 filename))))
	(when (memq mark flaglist)
	  (setq flaglist (delq mark flaglist))
	  (rename-file filename
		       (concat (elmo-match-string 1 filename)
			       (if flaglist
				   (char-list-to-string flaglist))))))))

(defsubst elmo-maildir-set-mark-msgs (folder locs mark)
  (dolist (loc locs)
    (elmo-maildir-set-mark
     (elmo-maildir-message-file-name folder loc)
     mark))
  t)

(defsubst elmo-maildir-delete-mark-msgs (folder locs mark)
  (dolist (loc locs)
    (elmo-maildir-delete-mark
     (elmo-maildir-message-file-name folder loc)
     mark))
  t)

(defsubst elmo-maildir-set-mark-messages (folder locations mark remove)
  (when mark
    (if remove
	(elmo-maildir-delete-mark-msgs folder locations mark)
      (elmo-maildir-set-mark-msgs folder locations mark))))

(luna-define-method elmo-map-folder-set-flag ((folder elmo-maildir-folder)
					      locations flag)
  (let ((spec (cdr (assq flag elmo-maildir-flag-specs))))
    (when spec
      (elmo-maildir-set-mark-messages folder locations
				      (car spec) (nth 1 spec)))))

(luna-define-method elmo-map-folder-unset-flag ((folder elmo-maildir-folder)
						locations flag)
  (let ((spec (cdr (assq flag elmo-maildir-flag-specs))))
    (when spec
      (elmo-maildir-set-mark-messages folder locations
				      (car spec) (not (nth 1 spec))))))

(luna-define-method elmo-folder-list-subfolders
  ((folder elmo-maildir-folder) &optional one-level)
  (let ((prefix (concat (elmo-folder-name-internal folder)
			(unless (string= (elmo-folder-prefix-internal folder)
					 (elmo-folder-name-internal folder))
			  elmo-path-sep)))
	(elmo-list-subdirectories-ignore-regexp
	 "^\\(\\.\\.?\\|cur\\|tmp\\|new\\)$")
	elmo-have-link-count)
    (append
     (list (elmo-folder-name-internal folder))
     (elmo-mapcar-list-of-list
      (function (lambda (x) (concat prefix x)))
      (elmo-list-subdirectories
       (elmo-maildir-folder-directory-internal folder)
       ""
       one-level)))))

(defvar elmo-maildir-sequence-number-internal 0)

(static-cond
 ((>= emacs-major-version 19)
  (defun elmo-maildir-make-unique-string ()
    "This function generates a string that can be used as a unique
file name for maildir directories."
     (let ((cur-time (current-time)))
       (format "%.0f.%d_%d.%s"
 	      (+ (* (car cur-time)
                    (float 65536)) (cadr cur-time))
	      (emacs-pid)
	      (incf elmo-maildir-sequence-number-internal)
	      (system-name)))))
 ((eq emacs-major-version 18)
  ;; A fake function for v18
  (defun elmo-maildir-make-unique-string ()
    "This function generates a string that can be used as a unique
file name for maildir directories."
    (unless (fboundp 'float-to-string)
      (load-library "float"))
    (let ((time (current-time)))
      (format "%s%d.%d.%s"
	      (substring
	       (float-to-string
		(f+ (f* (f (car time))
			(f 65536))
		    (f (cadr time))))
	       0 5)
	      (cadr time)
	      (% (abs (random t)) 10000); dummy pid
	      (system-name))))))

(defun elmo-maildir-temporal-filename (basedir)
  (let ((filename (expand-file-name
		   (concat "tmp/" (elmo-maildir-make-unique-string))
		   basedir)))
    (unless (file-exists-p (file-name-directory filename))
      (make-directory (file-name-directory filename)))
    (while (file-exists-p filename)
;;; I don't want to wait.
;;;   (sleep-for 2)
      (setq filename
	    (expand-file-name
	     (concat "tmp/" (elmo-maildir-make-unique-string))
	     basedir)))
    filename))

(luna-define-method elmo-folder-append-buffer ((folder elmo-maildir-folder)
					       &optional flags number)
  (let ((basedir (elmo-maildir-folder-directory-internal folder))
	(src-buf (current-buffer))
	dst-buf filename)
    (condition-case nil
	(with-temp-buffer
	  (setq filename (elmo-maildir-temporal-filename basedir))
	  (setq dst-buf (current-buffer))
	  (with-current-buffer src-buf
	    (copy-to-buffer dst-buf (point-min) (point-max)))
	  (as-binary-output-file
	   (write-region (point-min) (point-max) filename nil 'no-msg))
	  ;; add link from new.
	  ;; Some filesystem (like AFS) does not have hard-link.
	  ;; So we use elmo-copy-file instead of elmo-add-name-to-file here.
	  (elmo-copy-file
	   filename
	   (expand-file-name
	    (concat "new/" (file-name-nondirectory filename))
	    basedir))
	  (elmo-folder-preserve-flags
	   folder (elmo-msgdb-get-message-id-from-buffer) flags)
	  t)
      ;; If an error occured, return nil.
      (error))))

(luna-define-method elmo-folder-message-file-p ((folder elmo-maildir-folder))
  t)

(luna-define-method elmo-message-file-name ((folder elmo-maildir-folder)
					    number)
  (elmo-maildir-message-file-name
   folder
   (elmo-map-message-location folder number)))

(luna-define-method elmo-folder-message-make-temp-file-p
  ((folder elmo-maildir-folder))
  t)

(luna-define-method elmo-folder-message-make-temp-files ((folder
							  elmo-maildir-folder)
							 numbers
							 &optional
							 start-number)
  (let ((temp-dir (elmo-folder-make-temporary-directory folder))
	(cur-number (if start-number 0)))
    (dolist (number numbers)
      (elmo-copy-file
       (elmo-message-file-name folder number)
       (expand-file-name
	(int-to-string (if start-number (incf cur-number) number))
	temp-dir)))
    temp-dir))

(luna-define-method elmo-folder-append-messages :around
  ((folder elmo-maildir-folder)
   src-folder numbers &optional same-number)
  (if (elmo-folder-message-file-p src-folder)
      (let ((src-msgdb-exists (not (zerop (elmo-folder-length src-folder))))
	    (dir (elmo-maildir-folder-directory-internal folder))
	    (table (elmo-folder-flag-table folder))
	    (succeeds numbers)
	    filename flags id)
	(dolist (number numbers)
	  (setq flags (elmo-message-flags src-folder (car numbers))
		filename (elmo-maildir-temporal-filename dir))
	  (elmo-copy-file
	   (elmo-message-file-name src-folder number)
	   filename)
	  ;; Some filesystem (like AFS) does not have hard-link.
	  ;; So we use elmo-copy-file instead of elmo-add-name-to-file here.
	  (elmo-copy-file
	   filename
	   (expand-file-name
	    (concat "new/" (file-name-nondirectory filename))
	    dir))
	  ;; src folder's msgdb is loaded.
	  (when (setq id (and src-msgdb-exists
			      (elmo-message-field src-folder (car numbers)
						  'message-id)))
	    (elmo-flag-table-set table id flags))
	  (elmo-progress-notify 'elmo-folder-move-messages))
	(when (elmo-folder-persistent-p folder)
	  (elmo-folder-close-flag-table folder))
	succeeds)
    (luna-call-next-method)))

(luna-define-method elmo-map-folder-delete-messages
  ((folder elmo-maildir-folder) locations)
  (let (file)
    (dolist (location locations)
      (setq file (elmo-maildir-message-file-name folder location))
      (if (and file
	       (file-writable-p file)
	       (not (file-directory-p file)))
	  (delete-file file))))
  t)

(luna-define-method elmo-map-message-fetch ((folder elmo-maildir-folder)
					    location strategy
					    &optional section unseen)
  (let ((file (elmo-maildir-message-file-name folder location)))
    (when (file-exists-p file)
      (insert-file-contents-as-binary file)
      (unless unseen
	(elmo-map-folder-set-flag folder (list location) 'read))
      t)))

(luna-define-method elmo-folder-exists-p ((folder elmo-maildir-folder))
  (let ((basedir (elmo-maildir-folder-directory-internal folder)))
    (and (file-directory-p (expand-file-name "new" basedir))
	 (file-directory-p (expand-file-name "cur" basedir))
	 (file-directory-p (expand-file-name "tmp" basedir)))))

(luna-define-method elmo-folder-diff ((folder elmo-maildir-folder))
  (let* ((dir (elmo-maildir-folder-directory-internal folder))
	 (new-len (length (car (elmo-maildir-list-location dir "new"))))
	 (cur-len (length (car (elmo-maildir-list-location dir "cur")))))
    (cons new-len (+ new-len cur-len))))

(luna-define-method elmo-folder-creatable-p ((folder elmo-maildir-folder))
  t)

(luna-define-method elmo-folder-writable-p ((folder elmo-maildir-folder))
  t)

(luna-define-method elmo-folder-create ((folder elmo-maildir-folder))
  (let ((basedir (elmo-maildir-folder-directory-internal folder)))
    (condition-case nil
	(progn
	  (dolist (dir '("." "new" "cur" "tmp"))
	    (setq dir (expand-file-name dir basedir))
	    (or (file-directory-p dir)
		(progn
		  (elmo-make-directory dir)
		  (set-file-modes dir 448))))
	  t)
      (error))))

(luna-define-method elmo-folder-delete ((folder elmo-maildir-folder))
  (let ((msgs (and (elmo-folder-exists-p folder)
		   (elmo-folder-list-messages folder))))
    (when (yes-or-no-p (format "%sDelete msgdb and substance of \"%s\"? "
			       (if (> (length msgs) 0)
				   (format "%d msg(s) exists. " (length msgs))
				 "")
			       (elmo-folder-name-internal folder)))
      (let ((basedir (elmo-maildir-folder-directory-internal folder)))
	(condition-case nil
	    (let ((tmp-files (directory-files
			      (expand-file-name "tmp" basedir)
			      t "[^.].*")))
	      ;; Delete files in tmp.
	      (dolist (file tmp-files)
		(delete-file file))
	      (dolist (dir '("new" "cur" "tmp" "."))
		(setq dir (expand-file-name dir basedir))
		(if (not (file-directory-p dir))
		    (error nil)
		  (elmo-delete-directory dir t))))
	  (error nil)))
      (elmo-msgdb-delete-path folder)
      t)))

(luna-define-method elmo-folder-rename-internal ((folder elmo-maildir-folder)
						 new-folder)
  (let* ((old (elmo-maildir-folder-directory-internal folder))
	 (new (elmo-maildir-folder-directory-internal new-folder))
	 (new-dir (directory-file-name (file-name-directory new))))
    (unless (file-directory-p old)
      (error "No such directory: %s" old))
    (when (file-exists-p new)
      (error "Already exists directory: %s" new))
    (unless (file-directory-p new-dir)
      (elmo-make-directory new-dir))
    (rename-file old new)
    t))

(require 'product)
(product-provide (provide 'elmo-maildir) (require 'elmo-version))

;;; elmo-maildir.el ends here
