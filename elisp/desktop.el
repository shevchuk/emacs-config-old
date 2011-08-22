
<!-- saved from url=(0062)http://repo.or.cz/w/emacs.git/blob_plain/HEAD:/lisp/desktop.el -->
<html><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></head><body><pre style="word-wrap: break-word; white-space: pre-wrap;">;;; desktop.el --- save partial status of Emacs when killed

;; Copyright (C) 1993-1995, 1997, 2000-2011  Free Software Foundation, Inc.

;; Author: Morten Welinder &lt;terra@diku.dk&gt;
;; Keywords: convenience
;; Favourite-brand-of-beer: None, I hate beer.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see &lt;http://www.gnu.org/licenses/&gt;.

;;; Commentary:

;; Save the Desktop, i.e.,
;;	- some global variables
;; 	- the list of buffers with associated files.  For each buffer also
;;		- the major mode
;;		- the default directory
;;		- the point
;;		- the mark &amp; mark-active
;;		- buffer-read-only
;;		- some local variables

;; To use this, use customize to turn on desktop-save-mode or add the
;; following line somewhere in your .emacs file:
;;
;;	(desktop-save-mode 1)
;;
;; For further usage information, look at the section
;; (info "(emacs)Saving Emacs Sessions") in the GNU Emacs Manual.

;; When the desktop module is loaded, the function `desktop-kill' is
;; added to the `kill-emacs-hook'.  This function is responsible for
;; saving the desktop when Emacs is killed.  Furthermore an anonymous
;; function is added to the `after-init-hook'.  This function is
;; responsible for loading the desktop when Emacs is started.

;; Special handling.
;; -----------------
;; Variables `desktop-buffer-mode-handlers' and `desktop-minor-mode-handlers'
;; are supplied to handle special major and minor modes respectively.
;; `desktop-buffer-mode-handlers' is an alist of major mode specific functions
;; to restore a desktop buffer.  Elements must have the form
;;
;;    (MAJOR-MODE . RESTORE-BUFFER-FUNCTION).
;;
;; Functions listed are called by `desktop-create-buffer' when `desktop-read'
;; evaluates the desktop file.  Buffers with a major mode not specified here,
;; are restored by the default handler `desktop-restore-file-buffer'.
;; `desktop-minor-mode-handlers' is an alist of functions to restore
;; non-standard minor modes.  Elements must have the form
;;
;;    (MINOR-MODE . RESTORE-FUNCTION).
;;
;; Functions are called by `desktop-create-buffer' to restore minor modes.
;; Minor modes not specified here, are restored by the standard minor mode
;; function.  If you write a module that defines a major or minor mode that
;; needs a special handler, then place code like

;;    (defun foo-restore-desktop-buffer
;;    ...
;;    (add-to-list 'desktop-buffer-mode-handlers
;;                 '(foo-mode . foo-restore-desktop-buffer))

;; or

;;    (defun bar-desktop-restore
;;    ...
;;    (add-to-list 'desktop-minor-mode-handlers
;;                 '(bar-mode . bar-desktop-restore))

;; in the module itself, and make sure that the mode function is
;; autoloaded.  See the docstrings of `desktop-buffer-mode-handlers' and
;; `desktop-minor-mode-handlers' for more info.

;; Minor modes.
;; ------------
;; Conventional minor modes (see node "Minor Mode Conventions" in the elisp
;; manual) are handled in the following way:
;; When `desktop-save' saves the state of a buffer to the desktop file, it
;; saves as `desktop-minor-modes' the list of names of those variables in
;; `minor-mode-alist' that have a non-nil value.
;; When `desktop-create' restores the buffer, each of the symbols in
;; `desktop-minor-modes' is called as function with parameter 1.
;; The variables `desktop-minor-mode-table' and `desktop-minor-mode-handlers'
;; are used to handle non-conventional minor modes.  `desktop-save' uses
;; `desktop-minor-mode-table' to map minor mode variables to minor mode
;; functions before writing `desktop-minor-modes'.  If a minor mode has a
;; variable name that is different form its function name, an entry

;;    (NAME RESTORE-FUNCTION)

;; should be added to `desktop-minor-mode-table'.  If a minor mode should not
;; be restored, RESTORE-FUNCTION should be set to nil.  `desktop-create' uses
;; `desktop-minor-mode-handlers' to lookup minor modes that needs a restore
;; function different from the usual minor mode function.
;; ---------------------------------------------------------------------------

;; By the way: don't use desktop.el to customize Emacs -- the file .emacs
;; in your home directory is used for that.  Saving global default values
;; for buffers is an example of misuse.

;; PLEASE NOTE: The kill ring can be saved as specified by the variable
;; `desktop-globals-to-save' (by default it isn't).  This may result in saving
;; things you did not mean to keep.  Use M-x desktop-clear RET.

;; Thanks to  hetrick@phys.uva.nl (Jim Hetrick)      for useful ideas.
;;            avk@rtsg.mot.com (Andrew V. Klein)     for a dired tip.
;;            chris@tecc.co.uk (Chris Boucher)       for a mark tip.
;;            f89-kam@nada.kth.se (Klas Mellbourn)   for a mh-e tip.
;;            kifer@sbkifer.cs.sunysb.edu (M. Kifer) for a bug hunt.
;;            treese@lcs.mit.edu (Win Treese)        for ange-ftp tips.
;;            pot@cnuce.cnr.it (Francesco Potorti`)  for misc. tips.
;; ---------------------------------------------------------------------------
;; TODO:
;;
;; Save window configuration.
;; Recognize more minor modes.
;; Save mark rings.

;;; Code:

(defvar desktop-file-version "206"
  "Version number of desktop file format.
Written into the desktop file and used at desktop read to provide
backward compatibility.")

;; ----------------------------------------------------------------------------
;; USER OPTIONS -- settings you might want to play with.
;; ----------------------------------------------------------------------------

(defgroup desktop nil
  "Save status of Emacs when you exit."
  :group 'frames)

;;;###autoload
(define-minor-mode desktop-save-mode
  "Toggle desktop saving mode.
With numeric ARG, turn desktop saving on if ARG is positive, off
otherwise.  If desktop saving is turned on, the state of Emacs is
saved from one session to another.  See variable `desktop-save'
and function `desktop-read' for details."
  :global t
  :group 'desktop)

;; Maintained for backward compatibility
(define-obsolete-variable-alias 'desktop-enable
                                'desktop-save-mode "22.1")

(defun desktop-save-mode-off ()
  "Disable `desktop-save-mode'.  Provided for use in hooks."
  (desktop-save-mode 0))

(defcustom desktop-save 'ask-if-new
  "Specifies whether the desktop should be saved when it is killed.
A desktop is killed when the user changes desktop or quits Emacs.
Possible values are:
   t             -- always save.
   ask           -- always ask.
   ask-if-new    -- ask if no desktop file exists, otherwise just save.
   ask-if-exists -- ask if desktop file exists, otherwise don't save.
   if-exists     -- save if desktop file exists, otherwise don't save.
   nil           -- never save.
The desktop is never saved when `desktop-save-mode' is nil.
The variables `desktop-dirname' and `desktop-base-file-name'
determine where the desktop is saved."
  :type
  '(choice
    (const :tag "Always save" t)
    (const :tag "Always ask" ask)
    (const :tag "Ask if desktop file is new, else do save" ask-if-new)
    (const :tag "Ask if desktop file exists, else don't save" ask-if-exists)
    (const :tag "Save if desktop file exists, else don't" if-exists)
    (const :tag "Never save" nil))
  :group 'desktop
  :version "22.1")

(defcustom desktop-load-locked-desktop 'ask
  "Specifies whether the desktop should be loaded if locked.
Possible values are:
   t    -- load anyway.
   nil  -- don't load.
   ask  -- ask the user.
If the value is nil, or `ask' and the user chooses not to load the desktop,
the normal hook `desktop-not-loaded-hook' is run."
  :type
  '(choice
    (const :tag "Load anyway" t)
    (const :tag "Don't load" nil)
    (const :tag "Ask the user" ask))
  :group 'desktop
  :version "22.2")

(define-obsolete-variable-alias 'desktop-basefilename
                                'desktop-base-file-name "22.1")

(defcustom desktop-base-file-name
  (convert-standard-filename ".emacs.desktop")
  "Name of file for Emacs desktop, excluding the directory part."
  :type 'file
  :group 'desktop)

(defcustom desktop-base-lock-name
  (convert-standard-filename ".emacs.desktop.lock")
  "Name of lock file for Emacs desktop, excluding the directory part."
  :type 'file
  :group 'desktop
  :version "22.2")

(defcustom desktop-path (list "." user-emacs-directory "~")
  "List of directories to search for the desktop file.
The base name of the file is specified in `desktop-base-file-name'."
  :type '(repeat directory)
  :group 'desktop
  :version "23.2")                      ; user-emacs-directory added

(defcustom desktop-missing-file-warning nil
  "If non-nil, offer to recreate the buffer of a deleted file.
Also pause for a moment to display message about errors signaled in
`desktop-buffer-mode-handlers'.

If nil, just print error messages in the message buffer."
  :type 'boolean
  :group 'desktop
  :version "22.1")

(defcustom desktop-no-desktop-file-hook nil
  "Normal hook run when `desktop-read' can't find a desktop file.
Run in the directory in which the desktop file was sought.
May be used to show a dired buffer."
  :type 'hook
  :group 'desktop
  :version "22.1")

(defcustom desktop-not-loaded-hook nil
  "Normal hook run when the user declines to re-use a desktop file.
Run in the directory in which the desktop file was found.
May be used to deal with accidental multiple Emacs jobs."
  :type 'hook
  :group 'desktop
  :options '(desktop-save-mode-off save-buffers-kill-emacs)
  :version "22.2")

(defcustom desktop-after-read-hook nil
  "Normal hook run after a successful `desktop-read'.
May be used to show a buffer list."
  :type 'hook
  :group 'desktop
  :options '(list-buffers)
  :version "22.1")

(defcustom desktop-save-hook nil
  "Normal hook run before the desktop is saved in a desktop file.
Run with the desktop buffer current with only the header present.
May be used to add to the desktop code or to truncate history lists,
for example."
  :type 'hook
  :group 'desktop)

(defcustom desktop-globals-to-save
  '(desktop-missing-file-warning
    tags-file-name
    tags-table-list
    search-ring
    regexp-search-ring
    register-alist
    file-name-history)
  "List of global variables saved by `desktop-save'.
An element may be variable name (a symbol) or a cons cell of the form
\(VAR . MAX-SIZE), which means to truncate VAR's value to at most
MAX-SIZE elements (if the value is a list) before saving the value.
Feature: Saving `kill-ring' implies saving `kill-ring-yank-pointer'."
  :type '(repeat (restricted-sexp :match-alternatives (symbolp consp)))
  :group 'desktop)

(defcustom desktop-globals-to-clear
  '(kill-ring
    kill-ring-yank-pointer
    search-ring
    search-ring-yank-pointer
    regexp-search-ring
    regexp-search-ring-yank-pointer)
  "List of global variables that `desktop-clear' will clear.
An element may be variable name (a symbol) or a cons cell of the form
\(VAR . FORM).  Symbols are set to nil and for cons cells VAR is set
to the value obtained by evaluating FORM."
  :type '(repeat (restricted-sexp :match-alternatives (symbolp consp)))
  :group 'desktop
  :version "22.1")

(defcustom desktop-clear-preserve-buffers
  '("\\*scratch\\*" "\\*Messages\\*" "\\*server\\*" "\\*tramp/.+\\*"
    "\\*Warnings\\*")
  "List of buffers that `desktop-clear' should not delete.
Each element is a regular expression.  Buffers with a name matched by any of
these won't be deleted."
  :version "23.3"                       ; added Warnings - bug#6336
  :type '(repeat string)
  :group 'desktop)

;;;###autoload
(defcustom desktop-locals-to-save
  '(desktop-locals-to-save  ; Itself!  Think it over.
    truncate-lines
    case-fold-search
    case-replace
    fill-column
    overwrite-mode
    change-log-default-name
    line-number-mode
    column-number-mode
    size-indication-mode
    buffer-file-coding-system
    indent-tabs-mode
    tab-width
    indicate-buffer-boundaries
    indicate-empty-lines
    show-trailing-whitespace)
  "List of local variables to save for each buffer.
The variables are saved only when they really are local.  Conventional minor
modes are restored automatically; they should not be listed here."
  :type '(repeat symbol)
  :group 'desktop)

(defcustom desktop-buffers-not-to-save nil
  "Regexp identifying buffers that are to be excluded from saving."
  :type '(choice (const :tag "None" nil)
		 regexp)
  :version "23.2"                       ; set to nil
  :group 'desktop)

;; Skip tramp and ange-ftp files
(defcustom desktop-files-not-to-save
  "\\(^/[^/:]*:\\|(ftp)$\\)"
  "Regexp identifying files whose buffers are to be excluded from saving."
  :type '(choice (const :tag "None" nil)
		 regexp)
  :group 'desktop)

;; We skip TAGS files to save time (tags-file-name is saved instead).
(defcustom desktop-modes-not-to-save
  '(tags-table-mode)
  "List of major modes whose buffers should not be saved."
  :type '(repeat symbol)
  :group 'desktop)

(defcustom desktop-file-name-format 'absolute
  "Format in which desktop file names should be saved.
Possible values are:
   absolute -- Absolute file name.
   tilde    -- Relative to ~.
   local    -- Relative to directory of desktop file."
  :type '(choice (const absolute) (const tilde) (const local))
  :group 'desktop
  :version "22.1")

(defcustom desktop-restore-eager t
  "Number of buffers to restore immediately.
Remaining buffers are restored lazily (when Emacs is idle).
If value is t, all buffers are restored immediately."
  :type '(choice (const t) integer)
  :group 'desktop
  :version "22.1")

(defcustom desktop-lazy-verbose t
  "Verbose reporting of lazily created buffers."
  :type 'boolean
  :group 'desktop
  :version "22.1")

(defcustom desktop-lazy-idle-delay 5
  "Idle delay before starting to create buffers.
See `desktop-restore-eager'."
  :type 'integer
  :group 'desktop
  :version "22.1")

;;;###autoload
(defvar desktop-save-buffer nil
  "When non-nil, save buffer status in desktop file.
This variable becomes buffer local when set.

If the value is a function, it is called by `desktop-save' with argument
DESKTOP-DIRNAME to obtain auxiliary information to save in the desktop
file along with the state of the buffer for which it was called.

When file names are returned, they should be formatted using the call
\"(desktop-file-name FILE-NAME DESKTOP-DIRNAME)\".

Later, when `desktop-read' evaluates the desktop file, auxiliary information
is passed as the argument DESKTOP-BUFFER-MISC to functions in
`desktop-buffer-mode-handlers'.")
(make-variable-buffer-local 'desktop-save-buffer)
(make-obsolete-variable 'desktop-buffer-modes-to-save
                        'desktop-save-buffer "22.1")
(make-obsolete-variable 'desktop-buffer-misc-functions
                        'desktop-save-buffer "22.1")

;;;###autoload
(defvar desktop-buffer-mode-handlers
  nil
  "Alist of major mode specific functions to restore a desktop buffer.
Functions listed are called by `desktop-create-buffer' when `desktop-read'
evaluates the desktop file.  List elements must have the form

   (MAJOR-MODE . RESTORE-BUFFER-FUNCTION).

Buffers with a major mode not specified here, are restored by the default
handler `desktop-restore-file-buffer'.

Handlers are called with argument list

   (DESKTOP-BUFFER-FILE-NAME DESKTOP-BUFFER-NAME DESKTOP-BUFFER-MISC)

Furthermore, they may use the following variables:

   desktop-file-version
   desktop-buffer-major-mode
   desktop-buffer-minor-modes
   desktop-buffer-point
   desktop-buffer-mark
   desktop-buffer-read-only
   desktop-buffer-locals

If a handler returns a buffer, then the saved mode settings
and variable values for that buffer are copied into it.

Modules that define a major mode that needs a special handler should contain
code like

   (defun foo-restore-desktop-buffer
   ...
   (add-to-list 'desktop-buffer-mode-handlers
                '(foo-mode . foo-restore-desktop-buffer))

Furthermore the major mode function must be autoloaded.")

;;;###autoload
(put 'desktop-buffer-mode-handlers 'risky-local-variable t)
(make-obsolete-variable 'desktop-buffer-handlers
                        'desktop-buffer-mode-handlers "22.1")

(defcustom desktop-minor-mode-table
  '((auto-fill-function auto-fill-mode)
    (vc-mode nil)
    (vc-dired-mode nil)
    (erc-track-minor-mode nil)
    (savehist-mode nil))
  "Table mapping minor mode variables to minor mode functions.
Each entry has the form (NAME RESTORE-FUNCTION).
NAME is the name of the buffer-local variable indicating that the minor
mode is active.  RESTORE-FUNCTION is the function to activate the minor mode.
RESTORE-FUNCTION nil means don't try to restore the minor mode.
Only minor modes for which the name of the buffer-local variable
and the name of the minor mode function are different have to be added to
this table.  See also `desktop-minor-mode-handlers'."
  :type 'sexp
  :group 'desktop)

;;;###autoload
(defvar desktop-minor-mode-handlers
  nil
  "Alist of functions to restore non-standard minor modes.
Functions are called by `desktop-create-buffer' to restore minor modes.
List elements must have the form

   (MINOR-MODE . RESTORE-FUNCTION).

Minor modes not specified here, are restored by the standard minor mode
function.

Handlers are called with argument list

   (DESKTOP-BUFFER-LOCALS)

Furthermore, they may use the following variables:

   desktop-file-version
   desktop-buffer-file-name
   desktop-buffer-name
   desktop-buffer-major-mode
   desktop-buffer-minor-modes
   desktop-buffer-point
   desktop-buffer-mark
   desktop-buffer-read-only
   desktop-buffer-misc

When a handler is called, the buffer has been created and the major mode has
been set, but local variables listed in desktop-buffer-locals has not yet been
created and set.

Modules that define a minor mode that needs a special handler should contain
code like

   (defun foo-desktop-restore
   ...
   (add-to-list 'desktop-minor-mode-handlers
                '(foo-mode . foo-desktop-restore))

Furthermore the minor mode function must be autoloaded.

See also `desktop-minor-mode-table'.")

;;;###autoload
(put 'desktop-minor-mode-handlers 'risky-local-variable t)

;; ----------------------------------------------------------------------------
(defvar desktop-dirname nil
  "The directory in which the desktop file should be saved.")

(defun desktop-full-file-name (&amp;optional dirname)
  "Return the full name of the desktop file in DIRNAME.
DIRNAME omitted or nil means use `desktop-dirname'."
  (expand-file-name desktop-base-file-name (or dirname desktop-dirname)))

(defun desktop-full-lock-name (&amp;optional dirname)
  "Return the full name of the desktop lock file in DIRNAME.
DIRNAME omitted or nil means use `desktop-dirname'."
  (expand-file-name desktop-base-lock-name (or dirname desktop-dirname)))

(defconst desktop-header
";; --------------------------------------------------------------------------
;; Desktop File for Emacs
;; --------------------------------------------------------------------------
" "*Header to place in Desktop file.")

(defvar desktop-delay-hook nil
  "Hooks run after all buffers are loaded; intended for internal use.")

;; ----------------------------------------------------------------------------
;; Desktop file conflict detection
(defvar desktop-file-modtime nil
  "When the desktop file was last modified to the knowledge of this Emacs.
Used to detect desktop file conflicts.")

(defun desktop-owner (&amp;optional dirname)
  "Return the PID of the Emacs process that owns the desktop file in DIRNAME.
Return nil if no desktop file found or no Emacs process is using it.
DIRNAME omitted or nil means use `desktop-dirname'."
  (let (owner)
    (and (file-exists-p (desktop-full-lock-name dirname))
	 (condition-case nil
	     (with-temp-buffer
	       (insert-file-contents-literally (desktop-full-lock-name dirname))
	       (goto-char (point-min))
	       (setq owner (read (current-buffer)))
	       (integerp owner))
	   (error nil))
	 owner)))

(defun desktop-claim-lock (&amp;optional dirname)
  "Record this Emacs process as the owner of the desktop file in DIRNAME.
DIRNAME omitted or nil means use `desktop-dirname'."
  (write-region (number-to-string (emacs-pid)) nil
		(desktop-full-lock-name dirname)))

(defun desktop-release-lock (&amp;optional dirname)
  "Remove the lock file for the desktop in DIRNAME.
DIRNAME omitted or nil means use `desktop-dirname'."
  (let ((file (desktop-full-lock-name dirname)))
    (when (file-exists-p file) (delete-file file))))

;; ----------------------------------------------------------------------------
(defun desktop-truncate (list n)
  "Truncate LIST to at most N elements destructively."
  (let ((here (nthcdr (1- n) list)))
    (when (consp here)
      (setcdr here nil))))

;; ----------------------------------------------------------------------------
;;;###autoload
(defun desktop-clear ()
  "Empty the Desktop.
This kills all buffers except for internal ones and those with names matched by
a regular expression in the list `desktop-clear-preserve-buffers'.
Furthermore, it clears the variables listed in `desktop-globals-to-clear'."
  (interactive)
  (desktop-lazy-abort)
  (dolist (var desktop-globals-to-clear)
    (if (symbolp var)
	(eval `(setq-default ,var nil))
      (eval `(setq-default ,(car var) ,(cdr var)))))
  (let ((buffers (buffer-list))
        (preserve-regexp (concat "^\\("
                                 (mapconcat (lambda (regexp)
                                              (concat "\\(" regexp "\\)"))
                                            desktop-clear-preserve-buffers
                                            "\\|")
                                 "\\)$")))
    (while buffers
      (let ((bufname (buffer-name (car buffers))))
         (or
           (null bufname)
           (string-match preserve-regexp bufname)
           ;; Don't kill buffers made for internal purposes.
           (and (not (equal bufname "")) (eq (aref bufname 0) ?\s))
           (kill-buffer (car buffers))))
      (setq buffers (cdr buffers))))
  (delete-other-windows))

;; ----------------------------------------------------------------------------
(unless noninteractive
  (add-hook 'kill-emacs-hook 'desktop-kill))

(defun desktop-kill ()
  "If `desktop-save-mode' is non-nil, do what `desktop-save' says to do.
If the desktop should be saved and `desktop-dirname'
is nil, ask the user where to save the desktop."
  (when (and desktop-save-mode
             (let ((exists (file-exists-p (desktop-full-file-name))))
               (or (eq desktop-save t)
                   (and exists (eq desktop-save 'if-exists))
		   ;; If it exists, but we aren't using it, we are going
		   ;; to ask for a new directory below.
                   (and exists desktop-dirname (eq desktop-save 'ask-if-new))
                   (and
                    (or (memq desktop-save '(ask ask-if-new))
                        (and exists (eq desktop-save 'ask-if-exists)))
                    (y-or-n-p "Save desktop? ")))))
    (unless desktop-dirname
      (setq desktop-dirname
            (file-name-as-directory
             (expand-file-name
	      (read-directory-name "Directory for desktop file: " nil nil t)))))
    (condition-case err
	(desktop-save desktop-dirname t)
      (file-error
       (unless (yes-or-no-p "Error while saving the desktop.  Ignore? ")
	 (signal (car err) (cdr err))))))
  ;; If we own it, we don't anymore.
  (when (eq (emacs-pid) (desktop-owner)) (desktop-release-lock)))

;; ----------------------------------------------------------------------------
(defun desktop-list* (&amp;rest args)
  (if (null (cdr args))
      (car args)
    (setq args (nreverse args))
    (let ((value (cons (nth 1 args) (car args))))
      (setq args (cdr (cdr args)))
      (while args
	(setq value (cons (car args) value))
	(setq args (cdr args)))
      value)))

;; ----------------------------------------------------------------------------
(defun desktop-buffer-info (buffer)
  (set-buffer buffer)
  (list
   ;; base name of the buffer; replaces the buffer name if managed by uniquify
   (and (fboundp 'uniquify-buffer-base-name) (uniquify-buffer-base-name))
   ;; basic information
   (desktop-file-name (buffer-file-name) desktop-dirname)
   (buffer-name)
   major-mode
   ;; minor modes
   (let (ret)
     (mapc
      #'(lambda (minor-mode)
	  (and (boundp minor-mode)
	       (symbol-value minor-mode)
	       (let* ((special (assq minor-mode desktop-minor-mode-table))
		      (value (cond (special (cadr special))
				   ((functionp minor-mode) minor-mode))))
		 (when value (add-to-list 'ret value)))))
      (mapcar #'car minor-mode-alist))
     ret)
   ;; point and mark, and read-only status
   (point)
   (list (mark t) mark-active)
   buffer-read-only
   ;; auxiliary information
   (when (functionp desktop-save-buffer)
     (funcall desktop-save-buffer desktop-dirname))
   ;; local variables
   (let ((locals desktop-locals-to-save)
	 (loclist (buffer-local-variables))
	 (ll))
     (while locals
       (let ((here (assq (car locals) loclist)))
	 (if here
	     (setq ll (cons here ll))
	   (when (member (car locals) loclist)
	     (setq ll (cons (car locals) ll)))))
       (setq locals (cdr locals)))
     ll)))

;; ----------------------------------------------------------------------------
(defun desktop-internal-v2s (value)
  "Convert VALUE to a pair (QUOTE . TXT); (eval (read TXT)) gives VALUE.
TXT is a string that when read and evaluated yields value.
QUOTE may be `may' (value may be quoted),
`must' (values must be quoted), or nil (value may not be quoted)."
  (cond
    ((or (numberp value) (null value) (eq t value) (keywordp value))
     (cons 'may (prin1-to-string value)))
    ((stringp value)
     (let ((copy (copy-sequence value)))
       (set-text-properties 0 (length copy) nil copy)
       ;; Get rid of text properties because we cannot read them
       (cons 'may (prin1-to-string copy))))
    ((symbolp value)
     (cons 'must (prin1-to-string value)))
    ((vectorp value)
     (let* ((special nil)
	    (pass1 (mapcar
		    (lambda (el)
		      (let ((res (desktop-internal-v2s el)))
			(if (null (car res))
			    (setq special t))
			res))
		    value)))
       (if special
	   (cons nil (concat "(vector "
			     (mapconcat (lambda (el)
					  (if (eq (car el) 'must)
					      (concat "'" (cdr el))
					    (cdr el)))
					pass1
					" ")
			     ")"))
	 (cons 'may (concat "[" (mapconcat 'cdr pass1 " ") "]")))))
    ((consp value)
     (let ((p value)
	   newlist
	   use-list*
	   anynil)
       (while (consp p)
	 (let ((q.txt (desktop-internal-v2s (car p))))
	   (or anynil (setq anynil (null (car q.txt))))
	   (setq newlist (cons q.txt newlist)))
	 (setq p (cdr p)))
       (if p
	   (let ((last (desktop-internal-v2s p)))
	     (or anynil (setq anynil (null (car last))))
	     (or anynil
		 (setq newlist (cons '(must . ".") newlist)))
	     (setq use-list* t)
	     (setq newlist (cons last newlist))))
       (setq newlist (nreverse newlist))
       (if anynil
	   (cons nil
		 (concat (if use-list* "(desktop-list* "  "(list ")
			 (mapconcat (lambda (el)
				      (if (eq (car el) 'must)
					  (concat "'" (cdr el))
					(cdr el)))
				    newlist
				    " ")
			 ")"))
	 (cons 'must
	       (concat "(" (mapconcat 'cdr newlist " ") ")")))))
    ((subrp value)
     (cons nil (concat "(symbol-function '"
		       (substring (prin1-to-string value) 7 -1)
		       ")")))
    ((markerp value)
     (let ((pos (prin1-to-string (marker-position value)))
	   (buf (prin1-to-string (buffer-name (marker-buffer value)))))
       (cons nil (concat "(let ((mk (make-marker)))"
			 " (add-hook 'desktop-delay-hook"
			 " (list 'lambda '() (list 'set-marker mk "
			 pos " (get-buffer " buf ")))) mk)"))))
    (t					 ; save as text
     (cons 'may "\"Unprintable entity\""))))

;; ----------------------------------------------------------------------------
(defun desktop-value-to-string (value)
  "Convert VALUE to a string that when read evaluates to the same value.
Not all types of values are supported."
  (let* ((print-escape-newlines t)
	 (float-output-format nil)
	 (quote.txt (desktop-internal-v2s value))
	 (quote (car quote.txt))
	 (txt (cdr quote.txt)))
    (if (eq quote 'must)
	(concat "'" txt)
      txt)))

;; ----------------------------------------------------------------------------
(defun desktop-outvar (varspec)
  "Output a setq statement for variable VAR to the desktop file.
The argument VARSPEC may be the variable name VAR (a symbol),
or a cons cell of the form (VAR . MAX-SIZE),
which means to truncate VAR's value to at most MAX-SIZE elements
\(if the value is a list) before saving the value."
  (let (var size)
    (if (consp varspec)
	(setq var (car varspec) size (cdr varspec))
      (setq var varspec))
    (when (boundp var)
      (when (and (integerp size)
		 (&gt; size 0)
		 (listp (eval var)))
	(desktop-truncate (eval var) size))
      (insert "(setq "
	      (symbol-name var)
	      " "
	      (desktop-value-to-string (symbol-value var))
	      ")\n"))))

;; ----------------------------------------------------------------------------
(defun desktop-save-buffer-p (filename bufname mode &amp;rest _dummy)
  "Return t if buffer should have its state saved in the desktop file.
FILENAME is the visited file name, BUFNAME is the buffer name, and
MODE is the major mode.
\n\(fn FILENAME BUFNAME MODE)"
  (let ((case-fold-search nil)
        dired-skip)
    (and (not (and (stringp desktop-buffers-not-to-save)
		   (not filename)
		   (string-match desktop-buffers-not-to-save bufname)))
         (not (memq mode desktop-modes-not-to-save))
         ;; FIXME this is broken if desktop-files-not-to-save is nil.
         (or (and filename
		  (stringp desktop-files-not-to-save)
                  (not (string-match desktop-files-not-to-save filename)))
             (and (eq mode 'dired-mode)
                  (with-current-buffer bufname
                    (not (setq dired-skip
                               (string-match desktop-files-not-to-save
                                             default-directory)))))
             (and (null filename)
                  (null dired-skip)     ; bug#5755
		  (with-current-buffer bufname desktop-save-buffer))))))

;; ----------------------------------------------------------------------------
(defun desktop-file-name (filename dirname)
  "Convert FILENAME to format specified in `desktop-file-name-format'.
DIRNAME must be the directory in which the desktop file will be saved."
  (cond
    ((not filename) nil)
    ((eq desktop-file-name-format 'tilde)
     (let ((relative-name (file-relative-name (expand-file-name filename) "~")))
       (cond
         ((file-name-absolute-p relative-name) relative-name)
         ((string= "./" relative-name) "~/")
         ((string= "." relative-name) "~")
         (t (concat "~/" relative-name)))))
    ((eq desktop-file-name-format 'local) (file-relative-name filename dirname))
    (t (expand-file-name filename))))


;; ----------------------------------------------------------------------------
;;;###autoload
(defun desktop-save (dirname &amp;optional release)
  "Save the desktop in a desktop file.
Parameter DIRNAME specifies where to save the desktop file.
Optional parameter RELEASE says whether we're done with this desktop.
See also `desktop-base-file-name'."
  (interactive "DDirectory to save desktop file in: ")
  (setq desktop-dirname (file-name-as-directory (expand-file-name dirname)))
  (save-excursion
    (let ((eager desktop-restore-eager)
	  (new-modtime (nth 5 (file-attributes (desktop-full-file-name)))))
      (when
	  (or (not new-modtime)		; nothing to overwrite
	      (equal desktop-file-modtime new-modtime)
	      (yes-or-no-p (if desktop-file-modtime
			       (if (&gt; (float-time new-modtime) (float-time desktop-file-modtime))
				   "Desktop file is more recent than the one loaded.  Save anyway? "
				 "Desktop file isn't the one loaded.  Overwrite it? ")
			     "Current desktop was not loaded from a file.  Overwrite this desktop file? "))
	      (unless release (error "Desktop file conflict")))

	;; If we're done with it, release the lock.
	;; Otherwise, claim it if it's unclaimed or if we created it.
	(if release
	    (desktop-release-lock)
	  (unless (and new-modtime (desktop-owner)) (desktop-claim-lock)))

	(with-temp-buffer
	  (insert
	   ";; -*- mode: emacs-lisp; coding: emacs-mule; -*-\n"
	   desktop-header
	   ";; Created " (current-time-string) "\n"
	   ";; Desktop file format version " desktop-file-version "\n"
	   ";; Emacs version " emacs-version "\n")
	  (save-excursion (run-hooks 'desktop-save-hook))
	  (goto-char (point-max))
	  (insert "\n;; Global section:\n")
	  (mapc (function desktop-outvar) desktop-globals-to-save)
	  (when (memq 'kill-ring desktop-globals-to-save)
	    (insert
	     "(setq kill-ring-yank-pointer (nthcdr "
	     (int-to-string (- (length kill-ring) (length kill-ring-yank-pointer)))
	     " kill-ring))\n"))

	  (insert "\n;; Buffer section -- buffers listed in same order as in buffer list:\n")
	  (dolist (l (mapcar 'desktop-buffer-info (buffer-list)))
	    (let ((base (pop l)))
	      (when (apply 'desktop-save-buffer-p l)
		(insert "("
			(if (or (not (integerp eager))
				(if (zerop eager)
				    nil
				  (setq eager (1- eager))))
			    "desktop-create-buffer"
			  "desktop-append-buffer-args")
			" "
			desktop-file-version)
		;; If there's a non-empty base name, we save it instead of the buffer name
		(when (and base (not (string= base "")))
		  (setcar (nthcdr 1 l) base))
		(dolist (e l)
		  (insert "\n  " (desktop-value-to-string e)))
		(insert ")\n\n"))))

	  (setq default-directory desktop-dirname)
	  (let ((coding-system-for-write 'emacs-mule))
	    (write-region (point-min) (point-max) (desktop-full-file-name) nil 'nomessage))
	  ;; We remember when it was modified (which is presumably just now).
	  (setq desktop-file-modtime (nth 5 (file-attributes (desktop-full-file-name)))))))))

;; ----------------------------------------------------------------------------
;;;###autoload
(defun desktop-remove ()
  "Delete desktop file in `desktop-dirname'.
This function also sets `desktop-dirname' to nil."
  (interactive)
  (when desktop-dirname
    (let ((filename (desktop-full-file-name)))
      (setq desktop-dirname nil)
      (when (file-exists-p filename)
        (delete-file filename)))))

(defvar desktop-buffer-args-list nil
  "List of args for `desktop-create-buffer'.")

(defvar desktop-lazy-timer nil)

;; ----------------------------------------------------------------------------
;;;###autoload
(defun desktop-read (&amp;optional dirname)
  "Read and process the desktop file in directory DIRNAME.
Look for a desktop file in DIRNAME, or if DIRNAME is omitted, look in
directories listed in `desktop-path'.  If a desktop file is found, it
is processed and `desktop-after-read-hook' is run.  If no desktop file
is found, clear the desktop and run `desktop-no-desktop-file-hook'.
This function is a no-op when Emacs is running in batch mode.
It returns t if a desktop file was loaded, nil otherwise."
  (interactive)
  (unless noninteractive
    (setq desktop-dirname
          (file-name-as-directory
           (expand-file-name
            (or
             ;; If DIRNAME is specified, use it.
             (and (&lt; 0 (length dirname)) dirname)
             ;; Otherwise search desktop file in desktop-path.
             (let ((dirs desktop-path))
               (while (and dirs
                           (not (file-exists-p
                                 (desktop-full-file-name (car dirs)))))
                 (setq dirs (cdr dirs)))
               (and dirs (car dirs)))
             ;; If not found and `desktop-path' is non-nil, use its first element.
             (and desktop-path (car desktop-path))
             ;; Default: Home directory.
             "~"))))
    (if (file-exists-p (desktop-full-file-name))
	;; Desktop file found, but is it already in use?
	(let ((desktop-first-buffer nil)
	      (desktop-buffer-ok-count 0)
	      (desktop-buffer-fail-count 0)
	      (owner (desktop-owner))
	      ;; Avoid desktop saving during evaluation of desktop buffer.
	      (desktop-save nil))
	  (if (and owner
		   (memq desktop-load-locked-desktop '(nil ask))
		   (or (null desktop-load-locked-desktop)
		       (not (y-or-n-p (format "Warning: desktop file appears to be in use by PID %s.\n\
Using it may cause conflicts.  Use it anyway? " owner)))))
	      (let ((default-directory desktop-dirname))
		(setq desktop-dirname nil)
		(run-hooks 'desktop-not-loaded-hook)
		(unless desktop-dirname
		  (message "Desktop file in use; not loaded.")))
	    (desktop-lazy-abort)
	    ;; Evaluate desktop buffer and remember when it was modified.
	    (load (desktop-full-file-name) t t t)
	    (setq desktop-file-modtime (nth 5 (file-attributes (desktop-full-file-name))))
	    ;; If it wasn't already, mark it as in-use, to bother other
	    ;; desktop instances.
	    (unless owner
	      (condition-case nil
		  (desktop-claim-lock)
		(file-error (message "Couldn't record use of desktop file")
			    (sit-for 1))))

	    ;; `desktop-create-buffer' puts buffers at end of the buffer list.
	    ;; We want buffers existing prior to evaluating the desktop (and
	    ;; not reused) to be placed at the end of the buffer list, so we
	    ;; move them here.
	    (mapc 'bury-buffer
		  (nreverse (cdr (memq desktop-first-buffer (nreverse (buffer-list))))))
	    (switch-to-buffer (car (buffer-list)))
	    (run-hooks 'desktop-delay-hook)
	    (setq desktop-delay-hook nil)
	    (run-hooks 'desktop-after-read-hook)
	    (message "Desktop: %d buffer%s restored%s%s."
		     desktop-buffer-ok-count
		     (if (= 1 desktop-buffer-ok-count) "" "s")
		     (if (&lt; 0 desktop-buffer-fail-count)
			 (format ", %d failed to restore" desktop-buffer-fail-count)
		       "")
		     (if desktop-buffer-args-list
			 (format ", %d to restore lazily"
				 (length desktop-buffer-args-list))
		       ""))
	    t))
      ;; No desktop file found.
      (desktop-clear)
      (let ((default-directory desktop-dirname))
        (run-hooks 'desktop-no-desktop-file-hook))
      (message "No desktop file.")
      nil)))

;; ----------------------------------------------------------------------------
;; Maintained for backward compatibility
;;;###autoload
(defun desktop-load-default ()
  "Load the `default' start-up library manually.
Also inhibit further loading of it."
  (unless inhibit-default-init	        ; safety check
    (load "default" t t)
    (setq inhibit-default-init t)))
(make-obsolete 'desktop-load-default
               'desktop-save-mode "22.1")

;; ----------------------------------------------------------------------------
;;;###autoload
(defun desktop-change-dir (dirname)
  "Change to desktop saved in DIRNAME.
Kill the desktop as specified by variables `desktop-save-mode' and
`desktop-save', then clear the desktop and load the desktop file in
directory DIRNAME."
  (interactive "DChange to directory: ")
  (setq dirname (file-name-as-directory (expand-file-name dirname desktop-dirname)))
  (desktop-kill)
  (desktop-clear)
  (desktop-read dirname))

;; ----------------------------------------------------------------------------
;;;###autoload
(defun desktop-save-in-desktop-dir ()
  "Save the desktop in directory `desktop-dirname'."
  (interactive)
  (if desktop-dirname
      (desktop-save desktop-dirname)
    (call-interactively 'desktop-save))
  (message "Desktop saved in %s" (abbreviate-file-name desktop-dirname)))

;; ----------------------------------------------------------------------------
;;;###autoload
(defun desktop-revert ()
  "Revert to the last loaded desktop."
  (interactive)
  (unless desktop-dirname
    (error "Unknown desktop directory"))
  (unless (file-exists-p (desktop-full-file-name))
    (error "No desktop file found"))
  (desktop-clear)
  (desktop-read desktop-dirname))

(defvar desktop-buffer-major-mode)
(defvar desktop-buffer-locals)
(defvar auto-insert)  ; from autoinsert.el
;; ----------------------------------------------------------------------------
(defun desktop-restore-file-buffer (buffer-filename
                                    _buffer-name
                                    _buffer-misc)
  "Restore a file buffer."
  (when buffer-filename
    (if (or (file-exists-p buffer-filename)
	    (let ((msg (format "Desktop: File \"%s\" no longer exists."
			       buffer-filename)))
	      (if desktop-missing-file-warning
		  (y-or-n-p (concat msg " Re-create buffer? "))
		(message "%s" msg)
		nil)))
	(let* ((auto-insert nil) ; Disable auto insertion
	       (coding-system-for-read
		(or coding-system-for-read
		    (cdr (assq 'buffer-file-coding-system
			       desktop-buffer-locals))))
	       (buf (find-file-noselect buffer-filename)))
	  (condition-case nil
	      (switch-to-buffer buf)
	    (error (pop-to-buffer buf)))
	  (and (not (eq major-mode desktop-buffer-major-mode))
	       (functionp desktop-buffer-major-mode)
	       (funcall desktop-buffer-major-mode))
	  buf)
      nil)))

(defun desktop-load-file (function)
  "Load the file where auto loaded FUNCTION is defined."
  (when function
    (let ((fcell (and (fboundp function) (symbol-function function))))
      (when (and (listp fcell)
                 (eq 'autoload (car fcell)))
        (load (cadr fcell))))))

;; ----------------------------------------------------------------------------
;; Create a buffer, load its file, set its mode, ...;
;; called from Desktop file only.

;; Just to silence the byte compiler.

(defvar desktop-first-buffer)          ; Dynamically bound in `desktop-read'

;; Bound locally in `desktop-read'.
(defvar desktop-buffer-ok-count)
(defvar desktop-buffer-fail-count)

(defun desktop-create-buffer
    (file-version
     buffer-filename
     buffer-name
     buffer-majormode
     buffer-minormodes
     buffer-point
     buffer-mark
     buffer-readonly
     buffer-misc
     &amp;optional
     buffer-locals)

  (let ((desktop-file-version	    file-version)
	(desktop-buffer-file-name   buffer-filename)
	(desktop-buffer-name	    buffer-name)
	(desktop-buffer-major-mode  buffer-majormode)
	(desktop-buffer-minor-modes buffer-minormodes)
	(desktop-buffer-point	    buffer-point)
	(desktop-buffer-mark	    buffer-mark)
	(desktop-buffer-read-only   buffer-readonly)
	(desktop-buffer-misc	    buffer-misc)
	(desktop-buffer-locals	    buffer-locals))
    ;; To make desktop files with relative file names possible, we cannot
    ;; allow `default-directory' to change. Therefore we save current buffer.
    (save-current-buffer
      ;; Give major mode module a chance to add a handler.
      (desktop-load-file desktop-buffer-major-mode)
      (let ((buffer-list (buffer-list))
	    (result
	     (condition-case-no-debug err
		 (funcall (or (cdr (assq desktop-buffer-major-mode
					 desktop-buffer-mode-handlers))
			      'desktop-restore-file-buffer)
			  desktop-buffer-file-name
			  desktop-buffer-name
			  desktop-buffer-misc)
	       (error
		(message "Desktop: Can't load buffer %s: %s"
			 desktop-buffer-name
			 (error-message-string err))
		(when desktop-missing-file-warning (sit-for 1))
		nil))))
	(if (bufferp result)
	    (setq desktop-buffer-ok-count (1+ desktop-buffer-ok-count))
	  (setq desktop-buffer-fail-count (1+ desktop-buffer-fail-count))
	  (setq result nil))
	;; Restore buffer list order with new buffer at end. Don't change
	;; the order for old desktop files (old desktop module behaviour).
	(unless (&lt; desktop-file-version 206)
	  (mapc 'bury-buffer buffer-list)
	  (when result (bury-buffer result)))
	(when result
	  (unless (or desktop-first-buffer (&lt; desktop-file-version 206))
	    (setq desktop-first-buffer result))
	  (set-buffer result)
	  (unless (equal (buffer-name) desktop-buffer-name)
	    (rename-buffer desktop-buffer-name t))
	  ;; minor modes
	  (cond ((equal '(t) desktop-buffer-minor-modes) ; backwards compatible
		 (auto-fill-mode 1))
		((equal '(nil) desktop-buffer-minor-modes) ; backwards compatible
		 (auto-fill-mode 0))
		(t
		 (dolist (minor-mode desktop-buffer-minor-modes)
		   ;; Give minor mode module a chance to add a handler.
		   (desktop-load-file minor-mode)
		   (let ((handler (cdr (assq minor-mode desktop-minor-mode-handlers))))
		     (if handler
			 (funcall handler desktop-buffer-locals)
		       (when (functionp minor-mode)
			 (funcall minor-mode 1)))))))
	  ;; Even though point and mark are non-nil when written by
	  ;; `desktop-save', they may be modified by handlers wanting to set
	  ;; point or mark themselves.
	  (when desktop-buffer-point
	    (goto-char
	     (condition-case err
		 ;; Evaluate point.  Thus point can be something like
		 ;; '(search-forward ...
		 (eval desktop-buffer-point)
	       (error (message "%s" (error-message-string err)) 1))))
	  (when desktop-buffer-mark
	    (if (consp desktop-buffer-mark)
		(progn
		  (set-mark (car desktop-buffer-mark))
		  (setq mark-active (car (cdr desktop-buffer-mark))))
	      (set-mark desktop-buffer-mark)))
	  ;; Never override file system if the file really is read-only marked.
	  (when desktop-buffer-read-only (setq buffer-read-only desktop-buffer-read-only))
	  (while desktop-buffer-locals
	    (let ((this (car desktop-buffer-locals)))
	      (if (consp this)
		  ;; an entry of this form `(symbol . value)'
		  (progn
		    (make-local-variable (car this))
		    (set (car this) (cdr this)))
		;; an entry of the form `symbol'
		(make-local-variable this)
		(makunbound this)))
	    (setq desktop-buffer-locals (cdr desktop-buffer-locals))))))))

;; ----------------------------------------------------------------------------
;; Backward compatibility -- update parameters to 205 standards.
(defun desktop-buffer (buffer-filename buffer-name buffer-majormode
		       mim pt mk ro tl fc cfs cr buffer-misc)
  (desktop-create-buffer 205 buffer-filename buffer-name
			 buffer-majormode (cdr mim) pt mk ro
			 buffer-misc
			 (list (cons 'truncate-lines tl)
			       (cons 'fill-column fc)
			       (cons 'case-fold-search cfs)
			       (cons 'case-replace cr)
			       (cons 'overwrite-mode (car mim)))))

(defun desktop-append-buffer-args (&amp;rest args)
  "Append ARGS at end of `desktop-buffer-args-list'.
ARGS must be an argument list for `desktop-create-buffer'."
  (setq desktop-buffer-args-list (nconc desktop-buffer-args-list (list args)))
  (unless desktop-lazy-timer
    (setq desktop-lazy-timer
          (run-with-idle-timer desktop-lazy-idle-delay t 'desktop-idle-create-buffers))))

(defun desktop-lazy-create-buffer ()
  "Pop args from `desktop-buffer-args-list', create buffer and bury it."
  (when desktop-buffer-args-list
    (let* ((remaining (length desktop-buffer-args-list))
           (args (pop desktop-buffer-args-list))
           (buffer-name (nth 2 args))
           (msg (format "Desktop lazily opening %s (%s remaining)..."
                            buffer-name remaining)))
      (when desktop-lazy-verbose
        (message "%s" msg))
      (let ((desktop-first-buffer nil)
            (desktop-buffer-ok-count 0)
            (desktop-buffer-fail-count 0))
        (apply 'desktop-create-buffer args)
        (run-hooks 'desktop-delay-hook)
        (setq desktop-delay-hook nil)
        (bury-buffer (get-buffer buffer-name))
        (when desktop-lazy-verbose
          (message "%s%s" msg (if (&gt; desktop-buffer-ok-count 0) "done" "failed")))))))

(defun desktop-idle-create-buffers ()
  "Create buffers until the user does something, then stop.
If there are no buffers left to create, kill the timer."
  (let ((repeat 1))
    (while (and repeat desktop-buffer-args-list)
      (save-window-excursion
        (desktop-lazy-create-buffer))
      (setq repeat (sit-for 0.2))
    (unless desktop-buffer-args-list
      (cancel-timer desktop-lazy-timer)
      (setq desktop-lazy-timer nil)
      (message "Lazy desktop load complete")
      (sit-for 3)
      (message "")))))

(defun desktop-lazy-complete ()
  "Run the desktop load to completion."
  (interactive)
  (let ((desktop-lazy-verbose t))
    (while desktop-buffer-args-list
      (save-window-excursion
        (desktop-lazy-create-buffer)))
    (message "Lazy desktop load complete")))

(defun desktop-lazy-abort ()
  "Abort lazy loading of the desktop."
  (interactive)
  (when desktop-lazy-timer
    (cancel-timer desktop-lazy-timer)
    (setq desktop-lazy-timer nil))
  (when desktop-buffer-args-list
    (setq desktop-buffer-args-list nil)
    (when (called-interactively-p 'interactive)
      (message "Lazy desktop load aborted"))))

;; ----------------------------------------------------------------------------
;; When `desktop-save-mode' is non-nil and "--no-desktop" is not specified on the
;; command line, we do the rest of what it takes to use desktop, but do it
;; after finishing loading the init file.
;; We cannot use `command-switch-alist' to process "--no-desktop" because these
;; functions are processed after `after-init-hook'.
(add-hook
  'after-init-hook
  (lambda ()
    (let ((key "--no-desktop"))
      (when (member key command-line-args)
        (setq command-line-args (delete key command-line-args))
        (setq desktop-save-mode nil)))
    (when desktop-save-mode
      (desktop-read)
      (setq inhibit-startup-screen t))))

(provide 'desktop)

;;; desktop.el ends here
</pre></body><style type="text/css" style="display: none !important; ">/*This block of style rules is inserted by AdBlock*/#RadAd_Skyscraper,#bbccom_leaderboard,#center_banner,#footer_adcode,#hbBHeaderSpon,#hiddenHeaderSpon,#navbar_adcode,#rightAds,#rightcolumn_adcode,#top-advertising,#topMPU,#tracker_advertorial,.ad-now,.dfpad,.prWrap,[id^="ad_block"],[id^="adbrite"],[id^="dclkAds"],[id^="ew"][id$="_bannerDiv"],[id^="konaLayer"],[src*="sixsigmatraffic.com"],a.kLink span[id^="preLoadWrap"].preLoadWrap,a[href^="http://ad."][href*=".doubleclick.net/"],a[href^="http://adserver.adpredictive.com"],div#adxLeaderboard,div#dir_ads_site,div#FFN_Banner_Holder,div#FFN_imBox_Container,div#p360-format-box,div#rhs div#rhs_block table#mbEnd,div#rm_container,div#tads table[align="center"][width="100%"],div#tooltipbox[class^="itxt"],div[class^="dms_ad_IDS"],div[id^="adKontekst_"],div[id^="google_ads_div"],div[id^="kona_"][id$="_wrapper"],div[id^="sponsorads"],div[id^="y5_direct"],embed[flashvars*="AdID"],iframe.chitikaAdBlock,iframe[id^="dapIfM"],iframe[id^="etarget"][id$="banner"],iframe[name^="AdBrite"],iframe[name^="google_ads_"],img[src^="http://cdn.adnxs.com"],ispan#ab_pointer,object#flashad,object#ve_threesixty_swf[name="ve_threesixty_swf"],script[src="//pagead2.googleadservices.com/pagead/show_ads.js"] + ins > ins > iframe,script[src="http://pagead2.googlesyndication.com/pagead/show_ads.js"] + ins > ins > iframe,table[cellpadding="0"][width="100%"] > * > * > * > div[id^="tpa"],#A9AdsMiddleBoxTop,#A9AdsOutOfStockWidgetTop,#A9AdsServicesWidgetTop,#ADSLOT_1,#ADSLOT_2,#ADSLOT_3,#ADSLOT_4,#ADSLOT_SKYSCRAPER,#ADVERTISE_HERE_ROW,#AD_CONTROL_22,#AD_ROW,#AD_newsblock,#ADgoogle_newsblock,#ADsmallWrapper,#Ad1,#Ad160x600,#Ad2,#Ad300x250,#Ad3Left,#Ad3Right,#Ad3TextAd,#AdA,#AdArea,#AdBanner_F1,#AdBar,#AdBar1,#AdBox2,#AdC,#AdContainer,#AdContainerTop,#AdContentModule_F,#AdDetails_GoogleLinksBottom,#AdDetails_InsureWith,#AdE,#AdF,#AdFrame4,#AdG,#AdH,#AdHeader,#AdI,#AdJ,#AdLeaderboardBottom,#AdLeaderboardTop,#AdMiddle,#AdMobileLink,#AdPopUp,#AdRectangle,#AdSenseDiv,#AdServer,#AdShowcase_F1,#AdSky23,#AdSkyscraper,#AdSpacing,#AdSponsor_SF,#AdSubsectionShowcase_F1,#AdTargetControl1_iframe,#AdText,#AdTop,#AdTopLeader,#Ad_BelowContent,#Ad_Block,#Ad_Center1,#Ad_Right1,#Ad_RightBottom,#Ad_RightTop,#Ad_Top,#Adbanner,#Adrectangle,#Ads,#AdsContent,#AdsRight,#AdsWrap,#Ads_BA_CAD,#Ads_BA_CAD2,#Ads_BA_CAD_box,#Ads_BA_SKY,#Ads_CAD,#Ads_OV_BS,#Ads_Special,#AdvertMPU23b,#AdvertPanel,#AdvertiseFrame,#Advertisement,#Advertisements,#Advertorial,#Advertorials,#AdvertsBottom,#AdvertsBottomR,#BANNER_160x600,#BANNER_300x250,#BANNER_728x90,#BannerAd,#BannerAdvert,#BigBoxAd,#BodyAd,#BotAd,#Bottom468x60AD,#ButtonAd,#CompanyDetailsNarrowGoogleAdsPresentationControl,#CompanyDetailsWideGoogleAdsPresentationControl,#ContentAd,#ContentAd1,#ContentAd2,#ContentAdPlaceHolder1,#ContentAdPlaceHolder2,#ContentAdXXL,#ContentPolepositionAds_Result,#DartAd300x250,#DivAdEggHeadCafeTopBanner,#FIN_videoplayer_300x250ad,#FooterAd,#FooterAdContainer,#GoogleAd1,#GoogleAd2,#GoogleAd3,#GoogleAdsPlaceHolder,#GoogleAdsPresentationControl,#GoogleAdsense,#Google_Adsense_Main,#HEADERAD,#HOME_TOP_RIGHT_BOXAD,#HeaderAD,#HeaderAdsBlock,#HeaderAdsBlockFront,#HeaderBannerAdSpacer,#HeaderTextAd,#HeroAd,#HomeAd1,#HouseAd,#ID_Ad_Sky,#JobsearchResultsAds,#Journal_Ad_125,#Journal_Ad_300,#JuxtapozAds,#KH-contentAd,#LargeRectangleAd,#LeftAd,#LeftAdF1,#LeftAdF2,#LftAd,#LoungeAdsDiv,#LowerContentAd,#MainSponsoredLinks,#Nightly_adContainer,#NormalAdModule,#OpenXAds,#OverrideAdArea,#PREFOOTER_LEFT_BOXAD,#PREFOOTER_RIGHT_BOXAD,#PageLeaderAd,#RelevantAds,#RgtAd1,#RightAd,#RightBottom300x250AD,#RightNavTopAdSpot,#RightSponsoredAd,#SectionAd300-250,#SectionSponsorAd,#SideAdMpu,#SidebarAdContainer,#SkyAd,#SpecialAds,#SponsoredAd,#SponsoredLinks,#TL_footer_advertisement,#TOP_ADROW,#TOP_RIGHT_BOXAD,#Tadspacefoot,#Tadspacehead,#Tadspacemrec,#TextLinkAds,#ThreadAd,#Top468x60AD,#TopAd,#TopAdBox,#TopAdContainer,#TopAdDiv,#TopAdPos,#VM-MPU-adspace,#VM-footer-adspace,#VM-header-adspace,#VM-header-adwrap,#XEadLeaderboard,#XEadSkyscraper,#YahooAdParentContainer,#_ads,#abHeaderAdStreamer,#about_adsbottom,#abovepostads,#ad-120x600-sidebar,#ad-120x60Div,#ad-160x600,#ad-160x600-sidebar,#ad-250,#ad-250x300,#ad-300,#ad-300x250,#ad-300x250-sidebar,#ad-300x250Div,#ad-300x60-1,#ad-376x280,#ad-728,#ad-728x90,#ad-728x90-leaderboard-top,#ad-728x90-top0,#ad-ads,#ad-article,#ad-banner,#ad-banner-1,#ad-billboard-bottom,#ad-block-125,#ad-bottom,#ad-bottom-wrapper,#ad-box,#ad-box-first,#ad-box-second,#ad-boxes,#ad-bs,#ad-buttons,#ad-colB-1,#ad-column,#ad-container,#ad-content,#ad-contentad,#ad-first-post,#ad-flex-first,#ad-footer,#ad-footprint-160x600,#ad-frame,#ad-front-footer,#ad-front-sponsoredlinks,#ad-fullbanner2,#ad-globalleaderboard,#ad-halfpage,#ad-header,#ad-header-728x90,#ad-horizontal-header,#ad-img,#ad-inner,#ad-label,#ad-leaderboard,#ad-leaderboard-bottom,#ad-leaderboard-container,#ad-leaderboard-spot,#ad-leaderboard-top,#ad-left,#ad-left-sidebar-ad-1,#ad-left-sidebar-ad-2,#ad-left-sidebar-ad-3,#ad-links-content,#ad-list-row,#ad-lrec,#ad-medium,#ad-medium-rectangle,#ad-medrec,#ad-middlethree,#ad-middletwo,#ad-module,#ad-mpu,#ad-mpu1-spot,#ad-mpu2,#ad-mpu2-spot,#ad-north,#ad-one,#ad-placard,#ad-placeholder,#ad-rectangle,#ad-right,#ad-right-sidebar-ad-1,#ad-right-sidebar-ad-2,#ad-righttop,#ad-row,#ad-side-text,#ad-sidebar,#ad-sky,#ad-skyscraper,#ad-slug-wrapper,#ad-small-banner,#ad-space,#ad-special,#ad-splash,#ad-sponsors,#ad-spot,#ad-squares,#ad-target,#ad-target-Leaderbord,#ad-teaser,#ad-text,#ad-top,#ad-top-banner,#ad-top-text-low,#ad-top-wrap,#ad-tower,#ad-trailerboard-spot,#ad-two,#ad-typ1,#ad-unit,#ad-west,#ad-wrap,#ad-wrap-right,#ad-wrapper,#ad-wrapper1,#ad-yahoo-simple,#ad-zone-1,#ad-zone-2,#ad-zone-inline,#ad01,#ad02,#ad1006,#ad11,#ad125BL,#ad125BR,#ad125TL,#ad125TR,#ad125x125,#ad160x600,#ad160x600right,#ad1Sp,#ad2,#ad2Sp,#ad3,#ad300,#ad300-250,#ad300X250,#ad300_x_250,#ad300x100Middle,#ad300x150,#ad300x250,#ad300x250Module,#ad300x60,#ad300x600,#ad300x600_callout,#ad336,#ad336x280,#ad375x85,#ad4,#ad468,#ad468x60,#ad468x60_top,#ad526x250,#ad600,#ad7,#ad728,#ad728Mid,#ad728Top,#ad728Wrapper,#ad728top,#ad728x90,#ad728x90_1,#ad90,#adBadges,#adBanner,#adBanner10,#adBanner120x600,#adBanner160x600,#adBanner2,#adBanner3,#adBanner336x280,#adBanner4,#adBanner728,#adBanner9,#adBannerTable,#adBannerTop,#adBar,#adBelt,#adBlock125,#adBlockTop,#adBlocks,#adBottbanner,#adBox,#adBox11,#adBox16,#adBox350,#adBox390,#adCirc300X200,#adCirc_620_100,#adCol,#adColumn,#adCompanionSubstitute,#adComponentWrapper,#adContainer,#adContainer_1,#adContainer_2,#adContainer_3,#adDiv,#adDiv300,#adDiv728,#adFiller,#adFps,#adFtofrs,#adGallery,#adGoogleText,#adGroup1,#adHeader,#adHeaderTop,#adIsland,#adL,#adLB,#adLabel,#adLayer,#adLeader,#adLeaderTop,#adLeaderboard,#adMPU,#adMediumRectangle,#adMiddle0Frontpage,#adMiniPremiere,#adMonster1,#adOuter,#adP,#adPlaceHolderRight,#adPlacer,#adPosOne,#adRight,#adRight2,#adSPLITCOLUMNTOPRIGHT,#adSenseModule,#adSenseWrapper,#adServer_marginal,#adSidebar,#adSidebarSq,#adSky,#adSkyscraper,#adSlider,#adSpace,#adSpace0,#adSpace1,#adSpace10,#adSpace11,#adSpace12,#adSpace13,#adSpace14,#adSpace15,#adSpace16,#adSpace17,#adSpace18,#adSpace19,#adSpace2,#adSpace20,#adSpace21,#adSpace22,#adSpace23,#adSpace24,#adSpace25,#adSpace3,#adSpace300_ifrMain,#adSpace4,#adSpace5,#adSpace6,#adSpace7,#adSpace8,#adSpace9,#adSpace_footer,#adSpace_right,#adSpace_top,#adSpacer,#adSpecial,#adSplotlightEm,#adSpot-Leader,#adSpot-banner,#adSpot-island,#adSpot-mrec1,#adSpot-sponsoredlinks,#adSpot-textbox1,#adSpot-widestrip,#adSpotAdvertorial,#adSpotIsland,#adSpotSponsoredLinks,#adSquare,#adStaticA,#adStrip,#adSuperAd,#adSuperPremiere,#adSuperSkyscraper,#adSuperbanner,#adTableCell,#adTag1,#adTag2,#adText,#adTextCustom,#adTextLink,#adText_container,#adTile,#adTop,#adTopContent,#adTopbanner,#adTopboxright,#adTower,#adUnit,#adWrapper,#adZoneTop,#ad_1,#ad_130x250_inhouse,#ad_160x160,#ad_160x600,#ad_190x90,#ad_2,#ad_3,#ad_300,#ad_300_250,#ad_300_250_1,#ad_300a,#ad_300b,#ad_300c,#ad_300x250,#ad_300x250_content_column,#ad_300x250m,#ad_300x90,#ad_4,#ad_468_60,#ad_468x60,#ad_5,#ad_728_foot,#ad_728x90,#ad_728x90_container,#ad_940,#ad_984,#ad_A,#ad_B,#ad_Banner,#ad_C,#ad_C2,#ad_D,#ad_E,#ad_F,#ad_G,#ad_H,#ad_I,#ad_J,#ad_K,#ad_L,#ad_M,#ad_N,#ad_O,#ad_P,#ad_YieldManager-300x250,#ad_YieldManager-728x90,#ad_after_navbar,#ad_anchor,#ad_area,#ad_banner,#ad_banner_top,#ad_banners,#ad_bar,#ad_bellow_post,#ad_bigsize_wrapper,#ad_block_1,#ad_block_2,#ad_bottom,#ad_box,#ad_box_colspan,#ad_box_top,#ad_branding,#ad_bs_area,#ad_buttons,#ad_center_monster,#ad_circ300x250,#ad_cna2,#ad_cont,#ad_container,#ad_container_marginal,#ad_container_side,#ad_container_sidebar,#ad_container_top,#ad_content_top,#ad_content_wrap,#ad_feature,#ad_firstpost,#ad_footer,#ad_front_three,#ad_fullbanner,#ad_gallery,#ad_global_header,#ad_h3,#ad_haha_1,#ad_haha_4,#ad_halfpage,#ad_head,#ad_header,#ad_holder,#ad_horizontal,#ad_horseshoe_left,#ad_horseshoe_right,#ad_horseshoe_spacer,#ad_horseshoe_top,#ad_hotpots,#ad_in_arti,#ad_island,#ad_label,#ad_large_rectangular,#ad_lastpost,#ad_layer2,#ad_leader,#ad_leaderBoard,#ad_leaderboard,#ad_leaderboard728x90,#ad_leaderboard_top,#ad_left,#ad_lnk,#ad_lrec,#ad_lwr_square,#ad_main,#ad_medium_rectangle,#ad_medium_rectangular,#ad_mediumrectangle,#ad_menu_header,#ad_message,#ad_middle,#ad_most_pop_234x60_req_wrapper,#ad_mpu,#ad_mpu300x250,#ad_mpuav,#ad_mrcontent,#ad_newsletter,#ad_overlay,#ad_play_300,#ad_rect,#ad_rect_body,#ad_rect_bottom,#ad_rectangle,#ad_rectangle_medium,#ad_related_links_div,#ad_related_links_div_program,#ad_replace_div_0,#ad_replace_div_1,#ad_report_leaderboard,#ad_report_rectangle,#ad_results,#ad_right,#ad_right_main,#ad_ros_tower,#ad_rr_1,#ad_sec,#ad_sec_div,#ad_sgd,#ad_sidebar,#ad_sidebar1,#ad_sidebar2,#ad_sidebar3,#ad_sky,#ad_skyscraper,#ad_skyscraper160x600,#ad_skyscraper_text,#ad_slot_leaderboard,#ad_slot_livesky,#ad_slot_sky_top,#ad_space,#ad_square,#ad_ss,#ad_table,#ad_term_bottom_place,#ad_text:not(textarea),#ad_thread_first_post_content,#ad_top,#ad_top_holder,#ad_tp_banner_1,#ad_tp_banner_2,#ad_txt,#ad_unit,#ad_vertical,#ad_wide,#ad_wide_box,#ad_widget,#ad_window,#ad_wrap,#ad_wrapper,#adaptvcompanion,#adbForum,#adbanner,#adbar,#adbig,#adbnr,#adboard,#adbody,#adbottom,#adbox,#adbox1,#adbox2,#adbutton,#adclear,#adcode,#adcode1,#adcode2,#adcode3,#adcode4,#adcolumnwrapper,#adcontainer,#adcontainer1,#adcontainerRight,#adcontainsm,#adcontent,#adcontent1,#adcontrolPushSite,#add_ciao2,#addbottomleft,#addiv-bottom,#addiv-top,#adfooter,#adfooter_728x90,#adframe:not(frameset),#adhead,#adhead_g,#adheader,#adhome,#adiframe1_iframe,#adiframe2_iframe,#adiframe3_iframe,#adimg,#adition_content_ad,#adlabel,#adlabelFooter,#adlayerContainer,#adlayerad,#adleaderboard,#adleaderboard_flex,#adleaderboardb,#adleaderboardb_flex,#adleft,#adlinks,#adlinkws,#adlrec,#admanager_leaderboard,#admid,#admiddle3center,#admiddle3left,#adposition,#adposition-C,#adposition-FPMM,#adposition1,#adposition2,#adposition3,#adposition4,#adrectangle,#adrectanglea,#adrectanglea_flex,#adrectangleb,#adrectangleb_flex,#adrig,#adright,#adright2,#adrighthome,#ads-468,#ads-area,#ads-block,#ads-bot,#ads-bottom,#ads-col,#ads-dell,#ads-horizontal,#ads-indextext,#ads-leaderboard1,#ads-lrec,#ads-menu,#ads-middle,#ads-prices,#ads-rhs,#ads-right,#ads-sponsored-boxes,#ads-top,#ads-vers7,#ads-wrapper,#ads120,#ads160left,#ads2,#ads300,#ads300-250,#ads300Bottom,#ads300Top,#ads336x280,#ads7,#ads728bottom,#ads728top,#ads790,#adsDisplay,#adsID,#ads_160,#ads_300,#ads_728,#ads_banner,#ads_belowforumlist,#ads_belownav,#ads_bottom,#ads_bottom_inner,#ads_bottom_outer,#ads_box,#ads_button,#ads_catDiv,#ads_container,#ads_footer,#ads_fullsize,#ads_header,#ads_html1,#ads_html2,#ads_inner,#ads_lb,#ads_medrect,#ads_notice,#ads_right,#ads_right_sidebar,#ads_sidebar_roadblock,#ads_space,#ads_text,#ads_top,#ads_watch_top_square,#ads_zone27,#adsbottom,#adsbox,#adsbox-left,#adsbox-right,#adscolumn,#adsd_contentad_r1,#adsd_contentad_r2,#adsd_contentad_r3,#adsd_topbanner,#adsd_txt_sky,#adsdiv,#adsense,#adsense-2,#adsense-header,#adsense-tag,#adsense-text,#adsense03,#adsense04,#adsense05,#adsense1,#adsenseLeft,#adsenseOne,#adsenseWrap,#adsense_article_left,#adsense_box,#adsense_box_video,#adsense_inline,#adsense_leaderboard,#adsense_overlay,#adsense_placeholder_2,#adsenseheader,#adsensetopplay,#adsensewidget-3,#adserv,#adshometop,#adsimage,#adskinlink,#adsky,#adskyscraper,#adslider,#adslot,#adsmiddle,#adsonar,#adspace,#adspace-1,#adspace-300x250,#adspace300x250,#adspaceBox,#adspaceBox300,#adspace_header,#adspace_leaderboard,#adspacer,#adsponsorImg,#adspot,#adspot-1,#adspot-149x170,#adspot-1x4,#adspot-2,#adspot-295x60,#adspot-2a,#adspot-2b,#adspot-300x110-pos-1,#adspot-300x125,#adspot-300x250-pos-1,#adspot-300x250-pos-2,#adspot-468x60-pos-2,#adspot-a,#adspot300x250,#adspot_220x90,#adspot_300x250,#adspot_468x60,#adspot_728x90,#adsquare,#adsright,#adst,#adstop,#adt,#adtab,#adtag_right_side,#adtagfooter,#adtagheader,#adtagrightcol,#adtaily-widget-light,#adtech_googleslot_03c,#adtech_takeover,#adtext,#adtop,#adtophp,#adtxt,#adv-masthead,#adv_google_300,#adv_google_728,#adv_top_banner_wrapper,#adver1,#adver2,#adver3,#adver4,#adver5,#adver6,#adver7,#advert,#advert-1,#advert-120,#advert-boomer,#advert-display,#advert-header,#advert-leaderboard,#advert-links-bottom,#advert-skyscraper,#advert-top,#advert1,#advertBanner,#advertContainer,#advertDB,#advertRight,#advertSection,#advert_125x125,#advert_250x250,#advert_box,#advert_home01,#advert_leaderboard,#advert_lrec_format,#advert_mid,#advert_mpu,#advert_mpu_1,#advert_right_skyscraper,#advert_sky,#advertbox,#advertbox2,#advertbox3,#advertbox4,#adverthome,#advertise,#advertise-here-sidebar,#advertise-now,#advertise1,#advertiseHere,#advertisement160x600,#advertisement728x90,#advertisementLigatus,#advertisementPrio2,#advertisementRight,#advertisementRightcolumn0 { display:none !important; } #advertisementRightcolumn1,#advertisementsarticle,#advertiser-container,#advertiserLinks,#advertisers,#advertising,#advertising-banner,#advertising-caption,#advertising-container,#advertising-control,#advertising-skyscraper,#advertising-top,#advertising2,#advertisingModule160x600,#advertisingModule728x90,#advertisingTopWrapper,#advertising_btm,#advertising_contentad,#advertising_horiz_cont,#advertisment,#advertismentElementInUniversalbox,#advertorial,#advertorial_red_listblock,#adverts,#adverts-top-container,#adverts-top-left,#adverts-top-middle,#adverts-top-right,#advertsingle,#advertspace,#advt,#adwhitepaperwidget,#adwin_rec,#adwith,#adwords-4-container,#adwrapper,#adxBigAd,#adxMiddle5,#adxSponLink,#adxSponLinkA,#adxtop,#adz,#adzbanner,#adzerk,#adzerk1,#adzone,#adzoneBANNER,#adzoneheader,#affinityBannerAd,#after-content-ads,#after-header-ad-left,#after-header-ad-right,#after-header-ads,#agi-ad300x250,#agi-ad300x250overlay,#agi-sponsored,#alert_ads,#anchorAd,#annoying_ad,#ap_adframe,#ap_cu_overlay,#ap_cu_wrapper,#apiBackgroundAd,#apiTopAdWrap,#apmNADiv,#apolload,#araHealthSponsorAd,#area-adcenter,#area1ads,#article-ad-container,#article-box-ad,#articleAdReplacement,#articleLeftAdColumn,#articleSideAd,#article_ad,#article_ad_container,#article_box_ad,#articlead1,#articlead2,#asinglead,#atlasAdDivGame,#awds-nt1-ad,#babAdTop,#banner-300x250,#banner-ad,#banner-ad-container,#banner-ads,#banner250x250,#banner300x250,#banner468x60,#banner728x90,#bannerAd,#bannerAdTop,#bannerAdWrapper,#bannerAd_ctr,#banner_300_250,#banner_ad,#banner_ad_footer,#banner_ad_module,#banner_admicro,#banner_ads,#banner_content_ad,#banner_topad,#bannerad,#bannerad2,#baseAdvertising,#basket-adContainer,#bbccom_mpu,#bbo_ad1,#bg-footer-ads,#bg-footer-ads2,#bg_YieldManager-160x600,#bg_YieldManager-300x250,#bg_YieldManager-728x90,#bigAd,#bigBoxAd,#bigad300outer,#bigadbox,#bigadframe,#bigadspot,#billboard_ad,#block-ad_cube-1,#block-openads-0,#block-openads-1,#block-openads-2,#block-openads-3,#block-openads-4,#block-openads-5,#block-thewrap_ads_250x300-0,#block_advert,#blog-ad,#blog_ad_content,#blog_ad_opa,#blog_ad_right,#blog_ad_top,#blox-big-ad,#blox-big-ad-bottom,#blox-big-ad-top,#blox-halfpage-ad,#blox-tile-ad,#blox-tower-ad,#body_728_ad,#book-ad,#botad,#bott_ad2,#bott_ad2_300,#bottom-ad,#bottom-ad-container,#bottom-ad-wrapper,#bottom-ads,#bottomAd,#bottomAdCCBucket,#bottomAdContainer,#bottomAdSense,#bottomAdSenseDiv,#bottomAds,#bottomContentAd,#bottomRightAd,#bottomRightAdSpace,#bottom_ad,#bottom_ad_area,#bottom_ad_unit,#bottom_ads,#bottom_banner_ad,#bottom_overture,#bottom_sponsor_ads,#bottom_sponsored_links,#bottom_text_ad,#bottomad,#bottomads,#bottomadsense,#bottomadwrapper,#bottomleaderboardad,#box-ad-section,#box-content-ad,#box-googleadsense-1,#box-googleadsense-r,#box1ad,#boxAd300,#boxAdContainer,#boxAdvert,#box_ad,#box_advertisment,#box_mod_googleadsense,#boxad1,#boxad2,#boxad3,#boxad4,#boxad5,#bpAd,#bps-header-ad-container,#btnads,#btr_horiz_ad,#burn_header_ad,#button-ads-horizontal,#button-ads-vertical,#buttonAdWrapper1,#buttonAdWrapper2,#buttonAds,#buttonAdsContainer,#button_ad_container,#button_ad_wrap,#buttonad,#buy-sell-ads,#c4ad-Middle1,#c_ad_sb,#c_ad_sky,#caAdLarger,#catad,#category-ad,#cellAd,#channel_ad,#channel_ads,#ciHomeRHSAdslot,#circ_ad,#closeable-ad,#cmn_ad_box,#cmn_toolbar_ad,#cnnAboveFoldBelowAd,#cnnRR336ad,#cnnSponsoredPods,#cnnTopAd,#cnnVPAd,#col3_advertising,#colAd,#colRightAd,#collapseobj_adsection,#column4-google-ads,#comments-ad-container,#commercial_ads,#common_right_ad_wrapper,#common_right_lower_ad_wrapper,#common_right_lower_adspace,#common_right_lower_player_ad_wrapper,#common_right_lower_player_adspace,#common_right_player_ad_wrapper,#common_right_player_adspace,#common_right_right_adspace,#common_top_adspace,#comp_AdsLeaderboardTop,#companion-ad,#companionAdDiv,#companionad,#container-righttopads,#container-topleftads,#containerLocalAds,#containerLocalAdsInner,#containerMrecAd,#containerSqAd,#content-ad-header,#content-header-ad,#content-left-ad,#content-right-ad,#contentAd,#contentBoxad,#contentTopAds2,#content_ad,#content_ad_square,#content_ad_top,#content_ads_content,#content_box_300body_sponsoredoffers,#content_box_adright300_google,#content_mpu,#contentad,#contentad_imtext,#contentad_right,#contentads,#contentinlineAd,#contents_post_ad,#contextad,#contextual-ads,#contextual-ads-block,#contextualad,#coverADS,#coverads,#ctl00_Adspace_Top_Height,#ctl00_BottomAd,#ctl00_ContentMain_BanManAd468_BanManAd,#ctl00_ContentPlaceHolder1_blockAdd_divAdvert,#ctl00_ContentRightColumn_RightColumn_Ad1_BanManAd,#ctl00_ContentRightColumn_RightColumn_Ad2_BanManAd,#ctl00_ContentRightColumn_RightColumn_PremiumAd1_ucBanMan_BanManAd,#ctl00_LHTowerAd,#ctl00_LeftHandAd,#ctl00_MasterHolder_IBanner_adHolder,#ctl00_TopAd,#ctl00_TowerAd,#ctl00_VBanner_adHolder,#ctl00__Content__RepeaterReplies_ctl03__AdReply,#ctl00_abot_bb,#ctl00_adFooter,#ctl00_advert_LargeMPU_div_AdPlaceHolder,#ctl00_atop_bt,#ctl00_cphMain_hlAd1,#ctl00_cphMain_hlAd2,#ctl00_cphMain_hlAd3,#ctl00_ctl00_MainPlaceHolder_itvAdSkyscraper,#ctl00_ctl00_ctl00_Main_Main_PlaceHolderGoogleTopBanner_MPTopBannerAd,#ctl00_ctl00_ctl00_Main_Main_SideBar_MPSideAd,#ctl00_dlTilesAds,#ctl00_m_skinTracker_m_adLBL,#ctl00_phCrackerMain_ucAffiliateAdvertDisplayMiddle_pnlAffiliateAdvert,#ctl00_phCrackerMain_ucAffiliateAdvertDisplayRight_pnlAffiliateAdvert,#ctl00_topAd,#ctrlsponsored,#cubeAd,#cube_ads,#cube_ads_inner,#cubead,#cubead-2,#currencies-sponsored-by,#dAdverts,#dItemBox_ads,#dart_160x600,#dc-display-right-ad-1,#dcadSpot-Leader,#dcadSpot-LeaderFooter,#dcol-sponsored,#defer-adright,#detail_page_vid_topads,#div-gpt-ad-1,#div-gpt-ad-2,#div-gpt-ad-3,#div-gpt-ad-4,#divAd,#divAdBox,#divAdWrapper,#divAdvertisement,#divBottomad1,#divBottomad2,#divDoubleAd,#divLeftAd12,#divLeftRecAd,#divMenuAds,#divWNAdHeader,#divWrapper_Ad,#div_ad_leaderboard,#div_video_ads,#dlads,#dni-header-ad,#dnn_adLeaderBoard2008,#dnn_ad_banner,#download_ads,#dp_ads1,#ds-mpu,#ds_ad_north_leaderboard,#editorsmpu,#em_ad_superbanner,#embedded-ad,#evotopTen_advert,#ex-ligatus,#exads,#extra-search-ads,#fb_adbox,#fb_rightadpanel,#featuread,#featured-advertisements,#featuredAdContainer2,#featuredAds,#featured_ad_links,#feed_links_ad_container,#file_sponsored_link,#first-300-ad,#first-adlayer,#first_ad_unit,#firstad,#fl_hdrAd,#flash_ads_1,#flexiad,#floatingAd,#floating_ad_container,#foot-ad-1,#footad,#footer-ad,#footer-ads,#footer-advert,#footer-adverts,#footer-sponsored,#footerAd,#footerAdDiv,#footerAds,#footerAdvertisement,#footerAdverts,#footer_ad,#footer_ad_01,#footer_ad_block,#footer_ad_container,#footer_ad_modules,#footer_ads,#footer_adspace,#footer_text_ad,#footerad,#footerads,#footeradsbox,#forum_top_ad,#four_ads,#fpad1,#fpad2,#fpv_companionad,#fr_ad_center,#frame_admain,#frnAdSky,#frnBannerAd,#frnContentAd,#front_advert,#front_mpu,#ft-ad,#ft-ad-1,#ft-ad-container,#ft_mpu,#fullsizebanner_468x60,#fusionad,#fw-advertisement,#g_ad,#g_adsense,#ga_300x250,#gad,#gad2,#gad3,#gad5,#galleries-tower-ad,#gallery-ad,#gallery-ad-m0,#gallery-random-ad,#gallery_ads,#game-info-ad,#gamead,#gameads,#gasense,#gglads,#global_header_ad_area,#gm-ad-lrec,#gmi-ResourcePageAd,#gmi-ResourcePageLowerAd,#goad1,#goads,#gooadtop,#google-ad,#google-ad-art,#google-ad-table-right,#google-ad-tower,#google-ads,#google-ads-bottom,#google-ads-header,#google-ads-left-side,#google-adsense-mpusize,#googleAd,#googleAdArea,#googleAds,#googleAdsSml,#googleAdsense,#googleAdsenseBanner,#googleAdsenseBannerBlog,#googleAdwordsModule,#googleAfcContainer,#googleSearchAds,#googleShoppingAdsRight,#googleShoppingAdsTop,#googleSubAds,#google_ad,#google_ad_container,#google_ad_inline,#google_ad_test,#google_ads,#google_ads_aCol,#google_ads_frame1,#google_ads_frame1_anchor,#google_ads_frame2,#google_ads_frame2_anchor,#google_ads_frame3,#google_ads_frame3_anchor,#google_ads_test,#google_ads_top,#google_adsense_home_468x60_1,#googlead,#googlead-sidebar-middle,#googlead-sidebar-top,#googlead2,#googleadbox,#googleads,#googleadsense,#googlesponsor,#gpt-ad-halfpage,#gpt-ad-rectangle1,#gpt-ad-rectangle2,#gpt-ad-skyscraper,#gpt-ad-story_rectangle3,#grid_ad,#gsyadrectangleload,#gsyadrightload,#gsyadtop,#gsyadtopload,#gtopadvts,#half-page-ad,#halfPageAd,#halfe-page-ad-box,#hd-ads,#hd-banner-ad,#hdtv_ad_ss,#head-ad,#head-ad-1,#headAd,#head_ad,#head_advert,#headad,#header-ad,#header-ad-left,#header-ad-rectangle-container,#header-ad-right,#header-ad2010,#header-ads,#header-adspace,#header-advert,#header-advertisement,#header-advertising,#header-adverts,#headerAd,#headerAdBackground,#headerAdContainer,#headerAdWrap,#headerAds,#headerAdsWrapper,#headerTopAd,#header_ad,#header_ad_728_90,#header_ad_container,#header_adcode,#header_ads,#header_advertisement_top,#header_leaderboard_ad_container,#header_publicidad,#headerad,#headeradbox,#headerads,#headeradsbox,#headeradvertholder,#headeradwrap,#headline_ad,#headlinesAdBlock,#hiddenadAC,#hideads,#hl-sponsored-results,#hly_ad_side_bar_tower_left,#hly_inner_page_google_ad,#home-advert-module,#home-rectangle-ad,#home-top-ads,#homeMPU,#homeTopRightAd,#home_ad,#home_bottom_ad,#home_contentad,#home_feature_ad,#home_mpu,#home_spensoredlinks,#homead,#homepage-ad,#homepageAdsTop,#homepageFooterAd,#homepage_right_ad,#homepage_right_ad_container,#homepage_top_ads,#hometop_234x60ad,#hor_ad,#horizad,#horizontal-banner-ad,#horizontal_ad,#horizontal_ad_top,#horizontalads,#hot-deals-ad,#houseAd,#hp-header-ad,#hp-mpu,#hp-right-ad,#hp-store-ad,#hpV2_300x250Ad,#hpV2_googAds,#hp_ad300x250,#ibt_local_ad728,#icePage_SearchLinks_AdRightDiv,#icePage_SearchLinks_DownloadToolbarAdRightDiv,#icePage_SearchResults_ads0_SponsoredLink,#icePage_SearchResults_ads1_SponsoredLink,#icePage_SearchResults_ads2_SponsoredLink,#icePage_SearchResults_ads3_SponsoredLink,#icePage_SearchResults_ads4_SponsoredLink,#idSponsoredresultend,#idSponsoredresultstart,#imu_ad_module,#in_serp_ad,#inadspace,#indexad,#inline-story-ad,#inlineAd,#inlinead,#inlinegoogleads,#inlist-ad-block,#inner-advert-row,#inner-top-ads,#innerpage-ad,#inside-page-ad,#insider_ad_wrapper,#instoryad,#instoryadtext,#instoryadwrap,#int-ad,#interstitial_ad_wrapper,#iqadtile8,#islandAd,#j_ad,#ji_medShowAdBox,#jmp-ad-buttons,#joead,#joead2,#ka_adRightSkyscraperWide,#kaufDA-widget,#kdz_ad1,#kdz_ad2,#keyadvertcontainer,#landing-adserver,#lapho-top-ad-1,#largead,#lateAd,#layerAds_layerDiv,#layerTLDADSERV,#layer_ad_content,#layer_ad_main,#layerad,#leader-board-ad,#leaderAd,#leaderAdContainer,#leader_board_ad,#leaderad,#leaderad_section,#leaderboard-ad,#leaderboard-bottom-ad,#leaderboard_ad,#left-ad-1,#left-ad-2,#left-ad-col,#left-ad-skin,#left-bottom-ad,#left-lower-adverts,#left-lower-adverts-container,#leftAdContainer,#leftAd_rdr,#leftAdvert,#leftSectionAd300-100,#left_ad,#left_adspace,#leftad,#leftads,#leftcolAd,#lg-banner-ad,#ligatus,#linkAds,#linkads,#live-ad,#logoAd,#longAdSpace,#lowerAdvertisementImg,#lowerads,#lowerthirdad,#lowertop-adverts,#lowertop-adverts-container,#lpAdPanel,#lrecad,#lsadvert-left_menu_1,#lsadvert-left_menu_2,#lsadvert-top,#mBannerAd,#main-ad,#main-ad160x600,#main-ad160x600-img,#main-ad728x90,#main-advert1,#main-advert2,#main-advert3,#main-bottom-ad,#main-tj-ad,#mainAd,#mainAdUnit,#mainAdvert,#main_ad,#main_rec_ad,#main_top_ad_container,#marketing-promo,#mastAd,#mastAdvert,#mastad,#mastercardAd,#masthead_ad,#masthead_topad,#medRecAd,#media_ad,#mediaplayer_adburner,#mediumAdvertisement,#medrectad,#menuAds,#mi_story_assets_ad,#mid-ad300x250,#mid-table-ad,#midRightTextAds,#mid_ad_div,#mid_ad_title,#mid_mpu,#midadd,#midadspace,#middle-ad,#middle_ad,#middle_body_advertising,#middlead,#middleads,#midrect_ad,#midstrip_ad,#mini-ad,#mochila-column-right-ad-300x250,#mochila-column-right-ad-300x250-1,#module-google_ads,#module_ad,#module_box_ad,#module_sky_scraper,#monsterAd,#moogleAd,#moreads,#most_popular_ad,#motionAd,#mpu,#mpu-advert,#mpu-cont,#mpu300250,#mpuAd,#mpuDiv,#mpuSlot,#mpuWrapper,#mpuWrapperAd,#mpu_banner,#mpu_firstpost,#mpu_holder,#mpu_text_ad,#mpuad,#mpubox,#mr_banner_topad,#mrecAdContainer,#msAds,#ms_ad,#msad,#multiLinkAdContainer,#multi_ad,#my-ads,#myads_HeaderButton,#n_sponsor_ads,#namecom_ad_hosting_main,#narrow_ad_unit,#natadad300x250,#national_microlink_ads,#nationalad,#navi_banner_ad_780,#nba160PromoAd,#nba300Ad,#nbaGI300ad,#nbaHouseAnd600Ad,#nbaLeft600Ad,#nbaMidAds,#nbaVid300Ad,#nbcAd300x250,#new_topad,#newads,#news_advertorial_content,#news_advertorial_top,#ng_rtcol_ad,#noresults_ad_container,#noresultsads,#northad,#northbanner-advert,#northbanner-advert-container,#ns_ad1,#ns_ad2,#ns_ad3,#oanda_ads,#onespot-ads,#online_ad,#ovadsense,#p-googleadsense,#page-header-ad,#page-top-ad,#pageAds,#pageAdsDiv,#pageBannerAd,#page_ad,#page_content_top_ad,#pagelet_adbox,#pagelet_netego_ads,#pagelet_search_ads2,#panelAd,#pb_report_ad,#pcworldAdBottom,#pcworldAdTop,#pinball_ad,#player-below-advert,#player_ad,#player_ads,#pmad-in1,#pod-ad-video-page,#populate_ad_bottom,#populate_ad_left,#portlet-advertisement-left,#portlet-advertisement-right,#post-promo-ad,#post5_adbox,#post_ad,#premium_ad,#priceGrabberAd,#prime-ad-space,#print_ads,#printads,#product-adsense,#promo-ad,#promoAds,#ps-vertical-ads,#pub468x60,#publicidad,#pushdown_ad,#qm-ad-big-box,#qm-ad-sky,#qm-dvdad,#quigo_ad,#r1SoftAd,#rail_ad1,#rail_ad2,#realEstateAds,#rectAd,#rect_ad,#rectangle-ad,#rectangle_ad,#refine-300-ad,#region-node-advert,#region-top-ad,#rh-ad-container,#rh_tower_ad,#rhapsodyAd,#rhs_ads,#rhsadvert,#right-ad,#right-ad-col,#right-ad-skin,#right-ad-title,#right-ad1,#right-ads-3,#right-advert,#right-box-ad,#right-featured-ad,#right-mpu-1-ad-container,#right-uppder-adverts,#right-uppder-adverts-container,#rightAd,#rightAd300x250,#rightAd300x250Lower,#rightAdBar,#rightAdColumn,#rightAd_rdr,#rightAdsDiv,#rightColAd,#rightColumnMpuAd,#rightColumnSkyAd,#right_ad,#right_ad_wrapper,#right_ads,#right_advertisement,#right_advertising,#right_column_ad_container,#right_column_ads,#right_column_adverts,#right_column_internal_ad_container,#right_column_top_ad_unit,#rightad,#rightadContainer,#rightads,#rightadvertbar-doubleclickads,#rightbar-ad,#rightcolhouseads,#rightcolumn_300x250ad,#rightgoogleads,#rightinfoad,#rightside-ads,#rightside_ad,#righttop-adverts,#righttop-adverts-container,#rm_ad_text,#ros_ad,#rotatingads,#row2AdContainer,#rr_MSads,#rt-ad,#rt-ad-top,#rt-ad468,#rtMod_ad,#rtmod_ad,#sAdsBox,#sb-ad-sq,#sb_ad_links,#sb_advert,#search-google-ads,#search-sponsored-links,#search-sponsored-links-top,#searchAdSenseBox,#searchAdSenseBoxAd,#searchAdSkyscraperBox,#search_ads,#search_result_ad,#sec_adspace,#second-adlayer,#secondBoxAdContainer,#secondrowads,#sect-ad-300x100,#sect-ad-300x250-2,#section-ad-1-728,#section-ad-300-250,#section-ad-4-160,#section-blog-ad,#section-container-ddc_ads,#section_advertisements,#section_advertorial_feature,#servfail-ads,#sew-ad1,#shoppingads,#show-ad,#showAd,#showad,#side-ad,#side-ad-container,#side-ads,#sideAd,#sideAd1,#sideAd2,#sideAdSub,#sideBarAd,#side_ad,#side_ad_wrapper,#side_ads_by_google,#side_sky_ad,#sidead,#sideads,#sideadtop-to,#sidebar-125x125-ads,#sidebar-125x125-ads-below-index,#sidebar-ad,#sidebar-ad-boxes,#sidebar-ad-space,#sidebar-ad-wrap,#sidebar-ad3,#sidebar-ads,#sidebar2ads,#sidebar_ad,#sidebar_ad_widget,#sidebar_ads,#sidebar_ads_180,#sidebar_sponsoredresult_body,#sidebar_txt_ad_links,#sidebarad,#sidebaradpane,#sidebarads,#sidebaradver_advertistxt,#sideline-ad,#single-mpu,#singlead,#site-ad-container,#site-leaderboard-ads,#site_top_ad,#sitead,#sky-ad,#skyAd,#skyAdContainer,#skyScrapperAd,#skyWrapperAds,#sky_ad,#sky_advert,#skyads,#skyadwrap,#skyline_ad,#skyscrapeAd,#skyscraper-ad,#skyscraperAd,#skyscraperAdContainer,#skyscraper_ad,#skyscraper_advert,#skyscraperad,#slide_ad,#sliderAdHolder,#slideshow_ad_300x250,#sm-banner-ad,#small_ad,#small_ad_banners_vertical,#small_ads,#smallerAd,#some-ads,#some-more-ads,#specialAd_one,#specialAd_two,#specialadvertisingreport_container { display:none !important; } #specials_ads,#speeds_ads,#speeds_ads_fstitem,#speedtest_mrec_ad,#sphereAd,#sponlink,#sponlinks,#sponsAds,#sponsLinks,#sponseredlinks,#sponsorAd1,#sponsorAd2,#sponsorAdDiv,#sponsorLinks,#sponsorTextLink,#sponsor_banderole,#sponsor_deals,#sponsored,#sponsored-ads,#sponsored-features,#sponsored-links,#sponsored-listings,#sponsored-resources,#sponsored1,#sponsoredBox1,#sponsoredBox2,#sponsoredLinks,#sponsoredList,#sponsoredResults,#sponsoredResultsWide,#sponsoredSiteMainline,#sponsoredSiteSidebar,#sponsored_ads_v4,#sponsored_container,#sponsored_content,#sponsored_game_row_listing,#sponsored_head,#sponsored_links,#sponsored_v12,#sponsoredads,#sponsoredlinks,#sponsoredlinks_cntr,#sponsoredlinkslabel,#sponsoredresults_top,#sponsoredwellcontainerbottom,#sponsoredwellcontainertop,#sponsorlink,#spotlightAds,#spotlightad,#sqAd,#squareAd,#squareAdSpace,#squareAds,#square_ad,#start_middle_container_advertisment,#sticky-ad,#stickyBottomAd,#story-90-728-area,#story-ad-a,#story-ad-b,#story-leaderboard-ad,#story-sponsoredlinks,#storyAd,#storyAdWrap,#storyad2,#subpage-ad-right,#subpage-ad-top,#swads,#synch-ad,#systemad_background,#tabAdvertising,#takeoverad,#tblAd,#tbl_googlead,#tcwAd,#td-GblHdrAds,#template_ad_leaderboard,#tertiary_advertising,#test_adunit_160_article,#text-ad,#text-ads,#text-link-ads,#textAd,#textAds,#text_ad,#text_ads,#text_advert,#textad,#textad3,#textad_block,#the-last-ad-standing,#thefooterad,#themis-ads,#tile-ad,#tmglBannerAd,#tmp2_promo_ad,#toolbarSlideUpAd,#top-ad,#top-ad-container,#top-ad-menu,#top-ads,#top-ads-tabs,#top-advertisement,#top-banner-ad,#top-search-ad-wrapper,#topAd,#topAd728x90,#topAdBanner,#topAdBox,#topAdContainer,#topAdSenseDiv,#topAdcontainer,#topAds,#topAdsContainer,#topAdvert,#topBannerAd,#topBannerAdContainer,#topContentAdTeaser,#topNavLeaderboardAdHolder,#topOverallAdArea,#topRightBlockAdSense,#topSponsoredLinks,#top_ad,#top_ad_area,#top_ad_banner,#top_ad_game,#top_ad_unit,#top_ad_wrapper,#top_ad_zone,#top_ads,#top_advertise,#top_advertising,#top_rectangle_ad,#top_right_ad,#top_wide_ad,#topad,#topad1,#topad2,#topad_left,#topad_right,#topadbar,#topadblock,#topaddwide,#topads,#topadsense,#topadspace,#topadwrap,#topadzone,#topbanner_ad,#topbannerad,#topbar-ad,#topcustomad,#topleaderboardad,#topnav-ad-shell,#topnavad,#toprightAdvert,#toprightad,#topsponsored,#toptextad,#tour300Ad,#tourSponsoredLinksContainer,#towerad,#ts-ad_module,#ttp_ad_slot1,#ttp_ad_slot2,#twogamesAd,#txfPageMediaAdvertVideo,#txt_link_ads,#txtads,#undergameAd,#upperAdvertisementImg,#upperMpu,#upperad,#urban_contentad_1,#urban_contentad_2,#urban_contentad_article,#v_ad,#vert-ads,#vert_ad,#vert_ad_placeholder,#vertical_ad,#vertical_ads,#videoAd,#videoAdvert,#video_ads_overdiv,#video_advert2,#video_advert3,#video_cnv_ad,#video_overlay_ad,#videoadlogo,#viewportAds,#viewvid_ad300x250,#wall_advert,#wallpaper-ad-link,#wallpaperAd_left,#wallpaperAd_right,#walltopad,#weblink_ads_container,#welcomeAdsContainer,#welcome_ad_mrec,#welcome_advertisement,#wf_ContentAd,#wf_FrontSingleAd,#wf_SingleAd,#wf_bottomContentAd,#wgtAd,#whatsnews_top_ad,#whitepaper-ad,#whoisRightAdContainer,#wide_ad_unit_top,#wideskyscraper_160x600_left,#wideskyscraper_160x600_right,#widget_Adverts,#widget_advertisement,#widgetwidget_adserve2,#wrapAdRight,#wrapAdTop,#wrapperAdsTopLeft,#wrapperAdsTopRight,#xColAds,#y-ad-units,#y708-ad-expedia,#y708-ad-lrec,#y708-ad-partners,#y708-ad-ysm,#y708-advertorial-marketplace,#yahoo-ads,#yahoo-sponsors,#yahooSponsored,#yahoo_ads,#yahoo_ads_2010,#yahoo_text_ad,#yahooad-tbl,#yan-sponsored,#yatadsky,#ybf-ads,#yfi_fp_ad_mort,#yfi_fp_ad_nns,#yfi_pf_ad_mort,#ygrp-sponsored-links,#ymap_adbanner,#yn-gmy-ad-lrec,#yreSponsoredLinks,#ysm_ad_iframe,#zoneAdserverMrec,#zoneAdserverSuper,.ADBAR,.ADPod,.AD_ALBUM_ITEMLIST,.AD_MOVIE_ITEM,.AD_MOVIE_ITEMLIST,.AD_MOVIE_ITEMROW,.Ad-300x100,.Ad-Container-976x166,.Ad-Header,.Ad-MPU,.Ad-Wrapper-300x100,.Ad1,.Ad120x600,.Ad160x600,.Ad160x600left,.Ad160x600right,.Ad2,.Ad247x90,.Ad300x,.Ad300x250,.Ad300x250L,.Ad728x90,.AdBorder,.AdBox,.AdBox7,.AdContainerBox308,.AdContainerModule,.AdHeader,.AdHere,.AdInfo,.AdInline,.AdMedium,.AdPlaceHolder,.AdProS728x90Container,.AdProduct,.AdRingtone,.AdSense,.AdSenseLeft,.AdSlot,.AdSpace,.AdTextSmallFont,.AdTitle,.AdUnit,.AdUnit300,.Ad_C,.Ad_D_Wrapper,.Ad_E_Wrapper,.Ad_Right,.Ads,.AdsBottom,.AdsBoxBottom,.AdsBoxSection,.AdsBoxTop,.AdsLinks1,.AdsLinks2,.AdsRec,.Advert,.Advert300x250,.AdvertMidPage,.AdvertiseWithUs,.Advertisement,.AdvertisementTextTag,.Advman_Widget,.ArticleAd,.ArticleInlineAd,.BCA_Advertisement,.BannerAd,.BigBoxAd,.BlockAd,.BlueTxtAdvert,.BottomAdContainer,.BottomAffiliate,.BoxAd,.CG_adkit_leaderboard,.CG_details_ad_dropzone,.CWReviewsProdInfoAd,.ComAread,.CommentAd,.ContentAd,.ContentAds,.DAWRadvertisement,.DeptAd,.DisplayAd,.FT_Ad,.FeaturedAdIndexAd,.FlatAds,.GOOGLE_AD,.GoogleAd,.GoogleAdSenseBottomModule,.GoogleAdSenseRightModule,.HPG_Ad_B,.HPNewAdsBannerDiv,.HPRoundedAd,.HomeContentAd,.IABAdSpace,.InArticleAd,.IndexRightAd,.LazyLoadAd,.LeftAd,.LeftButtonAdSlot,.LeftTowerAd,.M2Advertisement,.MD_adZone,.MOS-ad-hack,.MPU,.MPUHolder,.MPUTitleWrapperClass,.MREC_ads,.MiddleAd,.MiddleAdContainer,.MiddleAdvert,.NewsAds,.OAS,.OpaqueAdBanner,.OpenXad,.PU_DoubleClickAdsContent,.Post5ad,.Post8ad,.Post9ad,.RBboxAd,.RW_ad300,.RectangleAd,.RelatedAds,.Right300x250AD,.RightAd1,.RightAdvertiseArea,.RightAdvertisement,.RightGoogleAFC,.RightRailAd,.RightRailTop300x250Ad,.RightSponsoredAdTitle,.RightTowerAd,.STR_AdBlock,.SectionSponsor,.SideAdCol,.SidebarAd,.SidebarAdvert,.SitesGoogleAdsModule,.SkyAdContainer,.SponsoredAdTitle,.SponsoredContent,.SponsoredLinkItemTD,.SponsoredLinks,.SponsoredLinksGrayBox,.SponsoredLinksModule,.SponsoredLinksPadding,.SponsoredLinksPanel,.Sponsored_link,.SquareAd,.StandardAdLeft,.StandardAdRight,.TRU-onsite-ads-leaderboard,.TextAd,.TheEagleGoogleAdSense300x250,.TopAd,.TopAdContainer,.TopAdL,.TopAdR,.TopBannerAd,.UIWashFrame_SidebarAds,.UnderAd,.VerticalAd,.Video-Ad,.VideoAd,.WidgetAdvertiser,.a160x600,.a728x90,.ad-120x60,.ad-120x600,.ad-160,.ad-160x600,.ad-160x600x1,.ad-160x600x2,.ad-160x600x3,.ad-250,.ad-300,.ad-300-block,.ad-300-blog,.ad-300x100,.ad-300x250,.ad-300x250-first,.ad-300x250-right0,.ad-300x600,.ad-350,.ad-355x75,.ad-600,.ad-635x40,.ad-728,.ad-728x90,.ad-728x90-1,.ad-728x90-top0,.ad-728x90_forum,.ad-90x600,.ad-above-header,.ad-adlink-bottom,.ad-adlink-side,.ad-area,.ad-background,.ad-banner,.ad-banner-smaller,.ad-bigsize,.ad-block,.ad-block-square,.ad-blog2biz,.ad-body,.ad-bottom,.ad-box,.ad-break,.ad-btn,.ad-btn-heading,.ad-button,.ad-cell,.ad-column,.ad-container,.ad-container-300x250,.ad-container-728x90,.ad-container-994x282,.ad-content,.ad-context,.ad-disclaimer,.ad-display,.ad-div,.ad-enabled,.ad-feedback,.ad-filler,.ad-flex,.ad-footer,.ad-footer-leaderboard,.ad-forum,.ad-google,.ad-graphic-large,.ad-gray,.ad-hdr,.ad-head,.ad-header,.ad-heading,.ad-holder,.ad-homeleaderboard,.ad-img,.ad-in-post,.ad-index-main,.ad-inline,.ad-island,.ad-label,.ad-leaderboard,.ad-links,.ad-lrec,.ad-medium,.ad-medium-two,.ad-mpl,.ad-mpu,.ad-msn,.ad-note,.ad-notice,.ad-other,.ad-permalink,.ad-place-active,.ad-placeholder,.ad-postText,.ad-poster,.ad-priority,.ad-rect,.ad-rectangle,.ad-rectangle-text,.ad-related,.ad-rh,.ad-ri,.ad-right,.ad-right-header,.ad-right-txt,.ad-row,.ad-section,.ad-show-label,.ad-side,.ad-sidebar,.ad-sidebar-outer,.ad-sidebar300,.ad-sky,.ad-skyscr,.ad-skyscraper,.ad-slot,.ad-slot-234-60,.ad-slot-300-250,.ad-slot-728-90,.ad-source,.ad-space,.ad-space-mpu-box,.ad-space-topbanner,.ad-spot,.ad-square,.ad-square300,.ad-squares,.ad-statement,.ad-story-inject,.ad-tabs,.ad-text,.ad-text-links,.ad-tile,.ad-title,.ad-top,.ad-top-left,.ad-unit,.ad-unit-300,.ad-unit-300-wrapper,.ad-unit-anchor,.ad-unit-top,.ad-vert,.ad-vertical-container,.ad-vtu,.ad-widget-list,.ad-with-us,.ad-wrap,.ad-wrapper,.ad-zone,.ad-zone-s-q-l,.ad.super,.ad0,.ad08,.ad08sky,.ad1,.ad10,.ad120,.ad120x240backgroundGray,.ad120x600,.ad125,.ad140,.ad160,.ad160600,.ad160x600,.ad160x600GrayBorder,.ad18,.ad19,.ad2,.ad21,.ad230,.ad250,.ad250c,.ad3,.ad300,.ad300250,.ad300_250,.ad300x100,.ad300x250,.ad300x250-hp-features,.ad300x250Module,.ad300x250Top,.ad300x250_container,.ad300x250box,.ad300x50-right,.ad300x600,.ad310,.ad336x280,.ad343x290,.ad4,.ad400right,.ad450,.ad468,.ad468_60,.ad468x60,.ad540x90,.ad6,.ad600,.ad620x70,.ad626X35,.ad7,.ad728,.ad728_90,.ad728x90,.ad728x90_container,.ad8,.ad90x780,.adAgate,.adArea674x60,.adBanner,.adBanner300x250,.adBanner728x90,.adBannerTyp1,.adBannerTypSortableList,.adBannerTypW300,.adBar,.adBgBottom,.adBgMId,.adBgTop,.adBlock,.adBottomLink,.adBottomboxright,.adBox,.adBox1,.adBox230X96,.adBox728X90,.adBoxBody,.adBoxBorder,.adBoxContainer,.adBoxContent,.adBoxInBignews,.adBoxSidebar,.adBoxSingle,.adBwrap,.adCMRight,.adCell,.adColumn,.adCont,.adContTop,.adContainer,.adContour,.adCreative,.adCube,.adDiv,.adElement,.adFender3,.adFrame,.adFtr,.adFullWidthMiddle,.adGoogle,.adHeader,.adHeadline,.adHolder,.adHome300x250,.adHorisontal,.adInNews,.adIsland,.adLabel,.adLeader,.adLeaderForum,.adLeaderboard,.adLeft,.adLoaded,.adLocal,.adMPU,.adMarker,.adMastheadLeft,.adMastheadRight,.adMegaBoard,.adMinisLR,.adMkt2Colw,.adModule,.adModuleAd,.adMpu,.adNewsChannel,.adNoOutline,.adNotice,.adNoticeOut,.adObj,.adPageBorderL,.adPageBorderR,.adPanel,.adPod,.adRect,.adResult,.adRight,.adSKY,.adSelfServiceAdvertiseLink,.adServer,.adSky,.adSky600,.adSkyscaper,.adSkyscraperHolder,.adSlot,.adSpBelow,.adSpace,.adSpacer,.adSplash,.adSponsor,.adSpot,.adSpot-brought,.adSpot-searchAd,.adSpot-textBox,.adSpot-twin,.adSpotIsland,.adSquare,.adSubColPod,.adSummary,.adSuperboard,.adSupertower,.adTD,.adTab,.adTag,.adText,.adTileWrap,.adTiler,.adTitle,.adTopLink,.adTopboxright,.adTout,.adTxt,.adUnit,.adUnitHorz,.adUnitVert,.adUnitVert_noImage,.adWebBoard,.adWidget,.adWithTab,.adWord,.adWrap,.adWrapper,.ad_0,.ad_1,.ad_120x90,.ad_125,.ad_130x90,.ad_160,.ad_160x600,.ad_2,.ad_200,.ad_200x200,.ad_250x250,.ad_250x250_w,.ad_3,.ad_300,.ad_300_250,.ad_300x250,.ad_300x250_box_right,.ad_336,.ad_336x280,.ad_350x100,.ad_350x250,.ad_400x200,.ad_468,.ad_468x60,.ad_600,.ad_728,.ad_728_90b,.ad_728x90,.ad_925x90,.ad_Left,.ad_Right,.ad_amazon,.ad_banner,.ad_banner_border,.ad_bar,.ad_bg,.ad_bigbox,.ad_biz,.ad_block,.ad_block_338,.ad_body,.ad_border,.ad_botbanner,.ad_bottom,.ad_bottom_leaderboard,.ad_bottom_left,.ad_box,.ad_box2,.ad_box_ad,.ad_box_div,.ad_callout,.ad_caption,.ad_column,.ad_column_box,.ad_column_hl,.ad_contain,.ad_container,.ad_content,.ad_content_wide,.ad_contents,.ad_descriptor,.ad_disclaimer,.ad_eyebrow,.ad_footer,.ad_frame,.ad_framed,.ad_front_promo,.ad_head,.ad_header,.ad_heading,.ad_headline,.ad_holder,.ad_hpm,.ad_info_block,.ad_inline,.ad_island,.ad_jnaught,.ad_label,.ad_launchpad,.ad_leader,.ad_leaderboard,.ad_left,.ad_line,.ad_link,.ad_links,.ad_linkunit,.ad_loc,.ad_lrec,.ad_main,.ad_medrec,.ad_medrect,.ad_middle,.ad_mod,.ad_mpu,.ad_mr,.ad_mrec,.ad_mrec_title_article,.ad_mrect,.ad_news,.ad_note,.ad_notice,.ad_one,.ad_p360,.ad_partner,.ad_partners,.ad_plus,.ad_post,.ad_power,.ad_promo,.ad_rec,.ad_rectangle,.ad_right,.ad_right_col,.ad_row,.ad_row_bottom_item,.ad_side,.ad_sidebar,.ad_skyscraper,.ad_slug,.ad_slug_table,.ad_space,.ad_space_300_250,.ad_spacer,.ad_sponsor,.ad_sponsoredsection,.ad_spot_b,.ad_spot_c,.ad_square_r,.ad_square_top,.ad_sub,.ad_tag_middle,.ad_text,.ad_text_w,.ad_title,.ad_top,.ad_top_leaderboard,.ad_top_left,.ad_topright,.ad_tower,.ad_unit,.ad_unit_rail,.ad_url,.ad_warning,.ad_wid300,.ad_wide,.ad_wrap,.ad_wrapper,.ad_wrapper_fixed,.ad_wrapper_top,.ad_wrp,.ad_zone,.adarea,.adarea-long,.adbanner,.adbannerbox,.adbannerright,.adbar,.adboard,.adborder,.adbot,.adbottom,.adbottomright,.adbox-outer,.adbox-wrapper,.adbox_300x600,.adbox_366x280,.adbox_468X60,.adbox_bottom,.adboxclass,.adbreak,.adbug,.adbutton,.adbuttons,.adcode,.adcol1,.adcol2,.adcolumn,.adcolumn_wrapper,.adcont,.adcopy,.add_300x250,.addiv,.adenquire,.adfieldbg,.adfoot,.adfootbox,.adframe,.adhead,.adhead_h,.adhead_h_wide,.adheader,.adheader100,.adhi,.adhint,.adholder,.adhoriz,.adi,.adiframe,.adinfo,.adinside,.adintro,.adits,.adjlink,.adkicker,.adkit,.adkit-advert,.adkit-lb-footer,.adlabel-horz,.adlabel-vert,.adlabelleft,.adleader,.adleaderboard,.adleft1,.adline,.adlink,.adlinks,.adlist,.adlnklst,.admarker,.admediumred,.admedrec,.admessage,.admodule,.admpu,.admpu-small,.adnation-banner,.adnotice,.adops,.adp-AdPrefix,.adpadding,.adpane,.adpic,.adprice,.adproxy,.adrec,.adright,.adroot,.adrotate_widget,.adrow,.adrow-post,.adrow1box1,.adrow1box3,.adrow1box4,.adrule,.ads-125,.ads-300,.ads-728x90-wrap,.ads-banner,.ads-below-content,.ads-categories-bsa,.ads-favicon,.ads-item,.ads-links-general,.ads-mpu,.ads-outer,.ads-profile,.ads-right,.ads-section,.ads-sidebar { display:none !important; } .ads-sky,.ads-small,.ads-sponsors,.ads-stripe,.ads-text,.ads-top,.ads-wide,.ads-widget,.ads-widget-partner-gallery,.ads03,.ads160,.ads1_250,.ads2,.ads3,.ads300,.ads460,.ads460_home,.ads468,.ads728,.ads728x90,.adsArea,.adsBelowHeadingNormal,.adsBlock,.adsBottom,.adsBox,.adsCell,.adsCont,.adsDiv,.adsFull,.adsImages,.adsInsideResults_v3,.adsMPU,.adsMiddle,.adsRight,.adsTextHouse,.adsTop,.adsTower2,.adsTowerWrap,.adsWithUs,.ads_125_square,.ads_180,.ads_300,.ads_300x250,.ads_320,.ads_337x280,.ads_728x90,.ads_big,.ads_big-half,.ads_box,.ads_box_headline,.ads_brace,.ads_catDiv,.ads_container,.ads_disc_anchor,.ads_disc_leader,.ads_disc_lwr_square,.ads_disc_skyscraper,.ads_disc_square,.ads_div,.ads_footer,.ads_header,.ads_holder,.ads_horizontal,.ads_leaderboard,.ads_lr_wrapper,.ads_medrect,.ads_mpu,.ads_outer,.ads_rectangle,.ads_remove,.ads_right,.ads_rightbar_top,.ads_sc_bl_i,.ads_sc_tb,.ads_sc_tl_i,.ads_show_if,.ads_side,.ads_sidebar,.ads_singlepost,.ads_spacer,.ads_takeover,.ads_title,.ads_top,.ads_top_promo,.ads_tr,.ads_verticalSpace,.ads_vtlLink,.ads_widesky,.ads_wrapperads_top,.adsafp,.adsbg300,.adsblockvert,.adsborder,.adsbottom,.adsbox,.adsboxitem,.adsbyyahoo,.adsc,.adscaleAdvert,.adsclick,.adscontainer,.adscreen,.adsd_shift100,.adsection_a2,.adsection_c2,.adsense-468,.adsense-ad,.adsense-category,.adsense-category-bottom,.adsense-googleAds,.adsense-heading,.adsense-overlay,.adsense-post,.adsense-right,.adsense-title,.adsense3,.adsense300,.adsenseAds,.adsenseBlock,.adsenseContainer,.adsenseGreenBox,.adsenseList,.adsense_bdc_v2,.adsense_mpu,.adsensebig,.adsenseblock,.adsenseblock_bottom,.adsenseblock_top,.adsenselr,.adsensem_widget,.adsensesq,.adsenvelope,.adset,.adsforums,.adsghori,.adsgvert,.adshome,.adside,.adsidebox,.adsider,.adsingle,.adsleft,.adsleftblock,.adslink,.adslogan,.adsmalltext,.adsmessage,.adsnippet_widget,.adsp,.adspace,.adspace-MR,.adspace-widget,.adspace180,.adspace_bottom,.adspace_buysell,.adspace_rotate,.adspace_skyscraper,.adspacer,.adspot,.adspot728x90,.adstextpad,.adstitle,.adstop,.adstory,.adstrip,.adtab,.adtable,.adtag,.adtech,.adtext,.adtext_gray,.adtext_horizontal,.adtext_onwhite,.adtext_vertical,.adtile,.adtips,.adtips1,.adtop,.adtravel,.adtxt,.adtxtlinks,.adunit,.adv-mpu,.adver,.adverTag,.adver_cont_below,.advert-300-side,.advert-300x100-side,.advert-728x90,.advert-article-bottom,.advert-bannerad,.advert-bg-250,.advert-box,.advert-btm,.advert-head,.advert-horizontal,.advert-iab-300-250,.advert-iab-468-60,.advert-mpu,.advert-skyscraper,.advert-text,.advert-title,.advert-txt,.advert120,.advert300,.advert300x250,.advert300x440,.advert4,.advert5,.advert8,.advertColumn,.advertCont,.advertContainer,.advertContent,.advertHeadline,.advertIslandWrapper,.advertRight,.advertSuperBanner,.advertText,.advertTitleSky,.advert_336,.advert_468x60,.advert_box,.advert_cont,.advert_container,.advert_djad,.advert_google_content,.advert_google_title,.advert_home_300,.advert_label,.advert_leaderboard,.advert_list,.advert_note,.advert_surr,.advert_top,.advertheader-red,.advertise,.advertise-here,.advertise-homestrip,.advertise-horz,.advertise-inquiry,.advertise-leaderboard,.advertise-list,.advertise-top,.advertise-vert,.advertiseContainer,.advertiseText,.advertise_ads,.advertise_here,.advertise_link,.advertise_link_sidebar,.advertisement,.advertisement-728x90,.advertisement-block,.advertisement-sidebar,.advertisement-space,.advertisement-sponsor,.advertisement-swimlane,.advertisement-text,.advertisement-top,.advertisement468,.advertisementBox,.advertisementColumnGroup,.advertisementContainer,.advertisementHeader,.advertisementLabel,.advertisementPanel,.advertisementText,.advertisement_300x250,.advertisement_btm,.advertisement_caption,.advertisement_g,.advertisement_header,.advertisement_horizontal,.advertisement_top,.advertiser,.advertiser-links,.advertisespace_div,.advertising-banner,.advertising-header,.advertising-leaderboard,.advertising-local-links,.advertising2,.advertisingTable,.advertising_block,.advertising_images,.advertisment,.advertisment_bar,.advertisment_two,.advertize,.advertize_here,.advertorial,.advertorial-2,.advertorial-promo-box,.advertorial_red,.advertorialtitle,.adverts,.adverts-125,.adverts_RHS,.advt,.advt-banner-3,.advt-block,.advt-sec,.advt300,.advt720,.adwordListings,.adwords,.adwordsHeader,.adwrap,.adwrapper,.adwrapper-lrec,.adwrapper948,.adzone-footer,.adzone-sidebar,.affiliate,.affiliate-link,.affiliate-sidebar,.affiliateAdvertText,.affinityAdHeader,.afsAdvertising,.after_ad,.agi-adsaleslinks,.alb-content-ad,.alignads,.alt_ad,.anchorAd,.another_text_ad,.answer_ad_content,.aolSponsoredLinks,.aopsadvert,.apiAdMarkerAbove,.apiAds,.app_advertising_skyscraper,.archive-ads,.art_ads,.article-ad-box,.article-ads,.article-content-adwrap,.articleAd,.articleAds,.articleAdsL,.articleEmbeddedAdBox,.article_ad,.article_adbox,.article_mpu_box,.article_page_ads_bottom,.articleads,.aseadn,.aux-ad-widget-1,.aux-ad-widget-2,.b-astro-sponsored-links_horizontal,.b-astro-sponsored-links_vertical,.b_ads_cont,.b_ads_top,.banmanad,.banner-468x60,.banner-ad,.banner-ads,.banner-advert,.banner-adverts,.banner-buysellads,.banner300by250,.banner300x100,.banner300x250,.banner468,.banner468by60,.banner728x90,.bannerAd,.bannerAdWrapper300x250,.bannerAdWrapper730x86,.bannerAdvert,.bannerRightAd,.banner_300x250,.banner_728x90,.banner_ad,.banner_ad_footer,.banner_ad_leaderboard,.bannerad,.bannerad-125tower,.bannerad-468x60,.barkerAd,.base-ad-mpu,.base_ad,.base_printer_widgets_AdBreak,.bg-ad-link,.bgnavad,.big-ads,.bigAd,.big_ad,.big_ads,.bigad,.bigad2,.bigbox_ad,.bigboxad,.billboard300x250,.billboard_ad,.biz-ad,.biz-ads,.biz-adtext,.blk_advert,.block-ad,.block-ad300,.block-admanager,.block-ads-bottom,.block-ads-top,.block-adsense,.block-adsense-managed,.block-adspace-full,.block-deca_advertising,.block-google_admanager,.block-openads,.block-openadstream,.block-openx,.block-thirdage-ads,.block-wtg_adtech,.blockAd,.blockAds,.block_ad,.block_ad_sb_text,.block_ad_sponsored_links,.block_ad_sponsored_links-wrapper,.block_ad_sponsored_links_localized,.blockad,.blocked-ads,.blog-ad-leader-inner,.blog-ads-container,.blogAd,.blogAdvertisement,.blogArtAd,.blogBigAd,.blog_ad,.blogads,.blox3featuredAd,.body_ad,.body_sponsoredresults_bottom,.body_sponsoredresults_middle,.body_sponsoredresults_top,.bodyads,.bodyads2,.bookseller-header-advt,.bottom-ad,.bottom-ad-fr,.bottomAd,.bottomAds,.bottom_ad,.bottom_ad_block,.bottom_ads,.bottom_adsense,.bottomad,.bottomads,.bottomadvert,.bottomrightrailAd,.bottomvidad,.box-ad,.box-ad-grey,.box-ads,.box-adsense,.boxAd,.boxAds,.boxAdsInclude,.box_ad,.box_ad_container,.box_ad_content,.box_ad_spacer,.box_ad_wrap,.box_ads,.box_advertising,.box_advertisment_62_border,.box_content_ad,.box_content_ads,.box_textads,.boxad,.boxads,.boxyads,.bps-ad-wrapper,.bps-advertisement,.bps-advertisement-inline-ads,.br-ad,.breakad_container,.brokerad,.bsa_ads,.btm_ad,.btn-ad,.bullet-sponsored-links,.bullet-sponsored-links-gray,.burstContentAdIndex,.busrep_poll_and_ad_container,.buttonAd,.buttonAds,.button_ads,.button_advert,.buttonadbox,.buttonads,.bx_ad,.bx_ad_right,.cA-adStrap,.cColumn-TextAdsBox,.c_ligatus_nxn,.calloutAd,.carbonad,.carbonad-tag,.care2_adspace,.catalog_ads,.category-ad,.categorySponsorAd,.category__big_game_container_body_games_advertising,.cb-ad-banner,.cb-ad-container,.cb_ads,.cb_navigation_ad,.cbstv_ad_label,.cbzadvert,.cbzadvert_block,.cdAdTitle,.cdmainlineSearchAdParent,.cdsidebarSearchAdParent,.centerAd,.center_ad,.centerad,.centered-ad,.chitikaAdCopy,.cinemabotad,.classifiedAdThree,.clearerad,.cmAdFind,.cm_ads,.cms-Advert,.cnbc_badge_banner_ad_area,.cnbc_banner_ad_area,.cnn160AdFooter,.cnnAd,.cnnMosaic160Container,.cnnStoreAd,.cnnStoryElementBoxAd,.cnnWCAdBox,.cnnWireAdLtgBox,.cnn_728adbin,.cnn_adcntr300x100,.cnn_adcntr728x90,.cnn_adspc336cntr,.cnn_adtitle,.cntrad,.column2-ad,.columnBoxAd,.columnRightAdvert,.com-ad-server,.comment-advertisement,.comment_ad_box,.common_advertisement_title,.communityAd,.conTSponsored,.conductor_ad,.confirm_ad_left,.confirm_ad_right,.confirm_leader_ad,.consoleAd,.container-adwords,.containerSqAd,.container_serendipity_plugin_google_adsense,.content-ad,.content-ads,.content-advert,.contentAd,.contentAdFoot,.contentAdsWrapper,.content_ad,.content_ad_728,.content_adsense,.content_adsq,.content_tagsAdTech,.contentad,.contentad300x250,.contentad_right_col,.contentadcontainer,.contentadfloatl,.contentadleft,.contentads,.contentadstartpage,.contenttextad,.contest_ad,.cp_ad,.cpmstarHeadline,.cpmstarText,.create_ad,.cs-mpu,.cscTextAd,.cse_ads,.cspAd,.ct_ad,.ctnAdSkyscraper,.ctnAdSquare300,.cube-ad,.cubeAd,.cube_ads,.currency_ad,.custom_ads,.cwAdvert,.cxAdvertisement,.darla_ad,.dart-ad,.dartAdImage,.dart_ad,.dart_tag,.dartadvert,.dartiframe,.dc-ad,.dcAdvertHeader,.deckAd,.deckads,.detail-ads,.detailMpu,.detail_ad,.detail_top_advert,.dfrads,.displayAdSlot,.divAd,.divAdright,.divad1,.divad2,.divad3,.divads,.divider_ad,.dlSponsoredLinks,.dmco_advert_iabrighttitle,.downloadAds,.download_ad,.downloadad,.dsq_ad,.dualAds,.dynamic-ads,.dynamic_ad,.e-ad,.ec-ads,.ec-ads-remove-if-empty,.em-ad,.em_ads_box_dynamic_remove,.embed-ad,.embeddedAd,.entry-body-ad,.entry-injected-ad,.entry_sidebar_ads,.entryad,.ez-clientAd,.f_Ads,.feature_ad,.featuredAds,.featuredadvertising,.firstpost_advert_container,.flagads,.flash-advertisement,.flash_ad,.flash_advert,.flashad,.flexiad,.flipbook_v2_sponsor_ad,.floatad,.floated_right_ad,.floatingAds,.fm-badge-ad,.fns_td_wrap,.fold-ads,.footad,.footer-ad,.footerAd,.footerAdModule,.footerAds,.footerAdslot,.footerAdverts,.footerTextAd,.footer_ad,.footer_ad336,.footer_ads,.footer_block_ad,.footer_bottomad,.footer_line_ad,.footer_text_ad,.footerad,.forumtopad,.freedownload_ads,.frn_adbox,.frn_cont_adbox,.frontads,.ft-ad,.ftdAdBar,.ftdContentAd,.full_ad_box,.fullbannerad,.g3rtn-ad-site,.gAdRows,.gAdSky,.gAdvertising,.g_ggl_ad,.ga-ads,.ga-textads-bottom,.ga-textads-top,.gaTeaserAdsBox,.gads,.gads_cb,.gads_container,.gallery_ad,.gam_ad_slot,.gameAd,.gamesPage_ad_content,.gbl_advertisement,.gen_side_ad,.gglAds,.global_banner_ad,.googad,.googads,.google-ad,.google-ad-container,.google-ads,.google-ads-boxout,.google-ads-slim,.google-right-ad,.google-sponsored-ads,.google-sponsored-link,.google468,.google468_60,.googleAd,.googleAd-content,.googleAd-list,.googleAd300x250_wrapper,.googleAdBox,.googleAdSense,.googleAdSenseModule,.googleAd_body,.googleAds,.googleAds_article_page_above_comments,.googleAdsense,.googleContentAds,.googleProfileAd,.googleSearchAd_content,.googleSearchAd_sidebar,.google_ad,.google_ad_wide,.google_add_container,.google_ads,.google_ads_bom_title,.google_ads_content,.google_adsense_footer,.googlead,.googleaddiv,.googleaddiv2,.googleads,.googleads_300x250,.googleads_title,.googleadsense,.googleafc,.googley_ads,.gpAdBox,.gpAds,.gradientAd,.grey-ad-line,.group_ad,.gsAd,.gsfAd,.gt_ad,.gt_ad_300x250,.gt_ad_728x90,.gt_adlabel,.gutter-ad-left,.gutter-ad-right,.gx_ad,.h-ad-728x90-bottom,.h_Ads,.h_ad,.half-ad,.half_ad_box,.hcf-ad-rectangle,.hcf-cms-ad,.hd_advert,.hdr-ads,.header-ad,.header-advert,.header-taxonomy-image-sponsor,.headerAd,.headerAds,.headerAdvert,.headerTextAd,.header_ad,.header_ad_center,.header_ad_div,.header_ads,.header_advertisement,.header_advertisment,.headerad,.headerad-720,.hi5-ad,.highlightsAd,.hm_advertisment,.hn-ads,.home-ad-links,.homeAd,.homeAd1,.homeAd2,.homeAdBoxA,.homeAdBoxBetweenBlocks,.homeAdBoxInBignews,.homeAdSection,.homeMediumAdGroup,.home_ad_bottom,.home_advertisement,.home_mrec_ad,.homead,.homepage-ad,.homepage300ad,.homepageFlexAdOuter,.homepageMPU,.homepage_middle_right_ad,.homepageinline_adverts,.hor_ad,.horiz_adspace,.horizontalAd,.horizontal_ad,.horizontal_ads,.horizontaltextadbox,.horizsponsoredlinks,.hortad,.houseAd1,.houseAdsStyle,.housead,.hoverad,.hp-col4-ads,.hp2-adtag,.hp_ad_cont,.hp_ad_text,.hp_t_ad,.hp_w_ad,.hpa-ad1,.html-advertisement,.ic-ads,.ico-adv,.idMultiAd,.image-advertisement,.imageAd,.imageads,.imgad,.in-page-ad,.in-story-ads,.in-story-text-ad,.inStoryAd-news2,.indEntrySquareAd,.indie-sidead,.indy_googleads,.inhousead,.inline-ad,.inline-mpu,.inline-mpu-left,.inlineSideAd,.inline_ad,.inline_ad_title,.inlinead,.inlineadsense,.inlineadtitle,.inlist-ad,.inlistAd,.inner-advt-banner-3,.innerAds,.innerad,.inpostad,.insert_advertisement,.insertad,.insideStoryAd,.inteliusAd_image,.interest-based-ad,.internalAdsContainer,.iprom-ad,.is24-adplace,.isAd,.islandAd,.islandAdvert,.islandad,.itemAdvertise,.jimdoAdDisclaimer,.jp-advertisment-promotional,.js-advert,.kdads-empty,.kdads-link,.kw_advert,.kw_advert_pair,.l_ad_sub,.l_banner.ads_show_if,.label-ad,.labelads,.largeRecAdNewsContainerRight,.largeRectangleAd,.largeUnitAd,.large_ad,.lastRowAd,.lcontentbox_ad,.leaderAdSlot,.leaderAdTop,.leaderAdvert,.leaderBoardAdHolder,.leaderOverallAdArea,.leader_ad,.leaderboardAd,.leaderboardAdContainer,.leaderboardAdContainerInner,.leaderboard_ad,.leaderboardad,.leaderboardadtop,.left-ad,.leftAd,.leftAdColumn,.leftAds,.left_ad,.left_ad_box,.left_adlink,.left_ads,.left_adsense,.leftad,.leftadtag,.leftbar_ad_160_600,.leftbarads,.leftbottomads,.leftnavad,.lgRecAd,.lg_ad,.ligatus,.linead,.link_adslider,.link_advertise,.live-search-list-ad-container,.ljad,.local-ads,.log_ads,.logoAds,.logoad,.logoutAd,.longAd,.longAdBox,.lowerAds,.m-ad-tvguide-box,.m4-adsbygoogle,.m_banner_ads,.macAd,.macad,.main-ad,.main-advert,.main-tabs-ad-block,.main_ad,.main_ad_bg_div,.main_adbox,.main_ads,.main_intro_ad,.map_media_banner_ad,.marginadsthin,.marketing-ad,.masthead_topad,.matador_sidebar_ad_600,.mdl-ad,.media-advert,.mediaAd,.mediaAdContainer,.mediaResult_sponsoredSearch,.medium-rectangle-ad,.mediumRectangleAdvert,.medium_ad,.medrect_ad,.member-ads,.menuItemBannerAd,.menueadimg,.messageBoardAd,.mf-ad300-container,.micro_ad,.mid_ad,.mid_page_ad,.midad,.middleAds,.middleads,.min_navi_ad,.mini-ad,.miniad,.mmc-ad,.mmcAd_Iframe,.mod-ad-lrec,.mod-ad-n,.mod-adopenx,.mod-vertical-ad,.mod_admodule,.module-ad,.module-ad-small,.module-ads,.moduleAd,.moduleAdvertContent,.module_ad,.module_box_ad,.modulegad,.moduletable-advert,.moduletable-googleads,.moduletablesquaread,.mpu,.mpu-ad,.mpu-advert,.mpu-footer,.mpu-fp,.mpu-title,.mpu-top-left { display:none !important; } .mpu-top-left-banner,.mpu-top-right,.mpu01,.mpuAd,.mpuAdSlot,.mpuAdvert,.mpuArea,.mpuBox,.mpuContainer,.mpuHolder,.mpuTextAd,.mpu_ad,.mpu_advert,.mpu_container,.mpu_gold,.mpu_holder,.mpu_platinum,.mpu_side,.mpu_text_ad,.mpuad,.mpuholderportalpage,.mrec_advert,.ms-ads-link,.msfg-shopping-mpu,.mvw_onPageAd1,.mwaads,.my-ad250x300,.nSponsoredLcContent,.nSponsoredLcTopic,.nadvt300,.narrow_ad_unit,.narrow_ads,.navAdsBanner,.navBads,.nav_ad,.navadbox,.navcommercial,.navi_ad300,.naviad,.nba300Ad,.nbaT3Ad160,.nbaTVPodAd,.nbaTwo130Ads,.nbc_ad_carousel_wrp,.newPex_forumads,.newTopAdContainer,.newad,.newsAd,.news_article_ad_google,.newsviewAdBoxInNews,.nf-adbox,.nn-mpu,.noAdForLead,.normalAds,.nrAds,.nsAdRow,.nu2ad,.oas-ad,.oas-bottom-ads,.oas_ad,.oas_advertisement,.offer_sponsoredlinks,.oio-banner-zone,.oio-link-sidebar,.oio-zone-position,.on_single_ad_box,.onethirdadholder,.openads,.openadstext_after,.openx,.openx-ad,.openx_ad,.osan-ads,.other_adv2,.outermainadtd1,.ovAdPromo,.ovAdSky,.ovAdartikel,.ov_spns,.ovadsenselabel,.pageAds,.pageBottomGoogleAd,.pageGoogleAd,.pageGoogleAdFlat,.pageGoogleAdSubcontent,.pageGoogleAds,.pageGoogleAdsContainer,.pageLeaderAd,.page_content_right_ad,.pagead,.pageads,.pagenavindexcontentad,.paneladvert,.partner-ad,.partner-ads-container,.partnersTextLinks,.pencil_ad,.player_ad_box,.player_hover_ad,.player_page_ad_box,.plista_inimg_box,.pm-ad,.pmad-in2,.pnp_ad,.pod-ad-300,.podRelatedAdLinksWidget,.podSponsoredLink,.portalCenterContentAdBottom,.portalCenterContentAdMiddle,.portalCenterContentAdTop,.portal_searchresultssponsoredlist,.portalcontentad,.post-ad,.postAd,.post_ad,.post_ads,.post_sponsor_unit,.postbit_adbit_register,.postbit_adcode,.postgroup-ads,.postgroup-ads-middle,.prebodyads,.premium_ad_container,.promoAd,.promoAds,.promo_ad,.ps-ligatus_placeholder,.pub_300x250,.pub_300x250m,.pub_728x90,.publication-ad,.publicidad,.puff-advertorials,.qa_ad_left,.qm-ad-content,.qm-ad-content-news,.quigo-ad,.qzvAdDiv,.r_ad_1,.r_ad_box,.r_ads,.rad_container,.rect_ad_module,.rectad,.rectangle-ad,.rectangleAd,.rectanglead,.redads_cont,.regular_728_ad,.regularad,.relatedAds,.related_post_google_ad,.remads,.resourceImagetAd,.result_ad,.reviewMidAdvertAlign,.rght300x250,.rhads,.rhs-ad,.rhs-ads-panel,.rhs-advert-container,.rhs-advert-link,.rhs-advert-title,.right-ad,.right-ad-holder,.right-ad2,.right-ads,.right-ads2,.right-sidebar-box-ad,.rightAd,.rightAdBox,.rightAdverts,.rightColAd,.rightColumnRectAd,.rightRailAd,.right_ad,.right_ad_160,.right_ad_box,.right_ad_common_block,.right_ad_text,.right_ad_top,.right_ads,.right_ads_column,.right_box_ad_rotating_container,.right_col_ad,.right_hand_advert_column,.right_side-partyad,.rightad,.rightad_1,.rightad_2,.rightadbox1,.rightads,.rightadunit,.rightcol_boxad,.rightcoladvert,.rightcoltowerad,.rnav_ad,.rngtAd,.roundedCornersAd,.roundingrayboxads,.rt_ad1_300x90,.rt_ad_300x250,.rt_ad_call,.s2k_ad,.savvyad_unit,.sb-ad-sq-bg,.sbAd,.sbAdUnitContainer,.sb_ad_holder,.sb_adsN,.sb_adsNv2,.sb_adsW,.sb_adsWv2,.scanAd,.scc_advert,.sci-ad-main,.sci-ad-sub,.search-ad,.search-results-ad,.search-sponsor,.search-sponsored,.searchAd,.searchAdTop,.searchAds,.searchSponsoredResultsBox,.searchSponsoredResultsList,.search_column_results_sponsored,.search_results_sponsored_top,.section-ad2,.section_mpu_wrapper,.section_mpu_wrapper_wrapper,.selfServeAds,.sepContentAd,.serp_sponsored,.servsponserLinks,.shoppingGoogleAdSense,.showAd_No,.showAd_Yes,.showcaseAd,.sidbaread,.side-ad,.side-ads,.side-sky-banner-160,.sideAd,.sideBoxAd,.side_ad,.side_ad2,.side_ad_1,.side_ad_2,.side_ad_3,.sidead,.sideads,.sideadsbox,.sideadvert,.sidebar-ad,.sidebar-ads,.sidebar-content-ad,.sidebar-text-ad,.sidebarAd,.sidebarAdUnit,.sidebarAdvert,.sidebar_ad,.sidebar_ad_300_250,.sidebar_ads,.sidebar_ads_336,.sidebar_adsense,.sidebar_box_ad,.sidebarad,.sidebarad_bottom,.sidebaradbox,.sidebarads,.sidebarboxad,.sideheadnarrowad,.sideheadsponsorsad,.single-google-ad,.singleAd,.singleAdsContainer,.singlead,.singleadstopcstm2,.site_ad_120_600,.site_ad_300x250,.sitesponsor,.skinAd,.skin_ad_638,.sky-ad,.skyAd,.skyAdd,.skyAdvert,.skyAdvert2,.sky_ad,.sky_scraper_ad,.skyad,.skyjobsadtext,.skyscraper-ad,.skyscraper_ad,.skyscraper_bannerAdHome,.sleekadbubble,.slideshow-ad,.slpBigSlimAdUnit,.slpSquareAdUnit,.sm_ad,.smallSkyAd1,.smallSkyAd2,.small_ad,.small_ads,.smallad-left,.smallads,.smallsponsorad,.smart_ads_bom_title,.specialAd175x90,.speedyads,.sphereAdContainer,.spl-ads,.spl_ad,.spl_ad2,.spl_ad_plus,.splitAd,.splitAdResultsPane,.sponlinkbox,.spons-link,.spons_links,.sponslink,.sponsor-ad,.sponsor-link,.sponsor-links,.sponsor-services,.sponsorPanel,.sponsorPost,.sponsorPostWrap,.sponsorStrip,.sponsor_ad_area,.sponsor_area,.sponsor_columns,.sponsor_footer,.sponsor_line,.sponsor_links,.sponsor_logo,.sponsoradtitle,.sponsored-ads,.sponsored-chunk,.sponsored-editorial,.sponsored-features,.sponsored-links,.sponsored-links-alt-b,.sponsored-links-holder,.sponsored-links-right,.sponsored-post,.sponsored-post_ad,.sponsored-results,.sponsored-right-border,.sponsored-text,.sponsoredBox,.sponsoredInfo,.sponsoredInner,.sponsoredLabel,.sponsoredLink,.sponsoredLinks,.sponsoredLinks2,.sponsoredLinksHeader,.sponsoredProduct,.sponsoredResults,.sponsoredSideInner,.sponsored_ads,.sponsored_box,.sponsored_box_search,.sponsored_by,.sponsored_link,.sponsored_links,.sponsored_links_title_container,.sponsored_links_title_container_top,.sponsored_links_top,.sponsored_result,.sponsored_results,.sponsored_well,.sponsoredibbox,.sponsoredlink,.sponsoredlinks,.sponsoredlinkscontainer,.sponsoredresults,.sponsoredtextlink_container_ovt,.sponsoring_link,.sponsorlink,.sponsorlink2,.sponsormsg,.sport-mpu-box,.spotlightAd,.squareAd,.square_ad,.square_banner_ad,.squared_ad,.ss-ad-mpu,.standard-ad,.start__newest__big_game_container_body_games_advertising,.staticAd,.stickyAdLink,.stock-ticker-ad-tag,.stocks-ad-tag,.store-ads,.story_AD,.story_ad_div,.story_right_adv,.storyad,.subad,.subadimg,.subcontent-ad,.subtitle-ad-container,.sugarad,.super-ad,.supercommentad_left,.supercommentad_right,.supp-ads,.supportAdItem,.surveyad,.t10ad,.tab_ad,.tab_ad_area,.tablebordersponsor,.tadsanzeige,.tadsbanner,.tadselement,.tallad,.tblTopAds,.tbl_ad,.tbox_ad,.td-Adholder,.td-TrafficWeatherWidgetAdGreyBrd,.teaser-sponsor,.teaserAdContainer,.teaser_adtiles,.text-ad,.text-ad-links,.text-ads,.text-advertisement,.text-g-advertisement,.text-g-group-short-rec-ad,.text-g-net-grp-google-ads-article-page,.textAd,.textAdBox,.textAds,.text_ad,.text_ads,.textad,.textadContainer,.textad_headline,.textadbox,.textadheadline,.textadlink,.textads,.textads_left,.textads_right,.textadsds,.textadsfoot,.textadtext,.textlink-ads,.textlinkads,.tf_page_ad_search,.thirdage_ads_300x250,.thirdage_ads_728x90,.thisIsAd,.thisIsAnAd,.ticket-ad,.tileAds,.tips_advertisement,.title-ad,.title_adbig,.tncms-region-ads,.toolad,.toolbar-ad,.top-ad,.top-ad-space,.top-ads,.top-banner-ad,.top-menu-ads,.topAd,.topAdWrap,.topAds,.topAdvertisement,.topAdverts,.topBannerAd,.topLeaderboardAd,.top_Ad,.top_ad,.top_ad_728,.top_ad_728_90,.top_ad_disclaimer,.top_ad_div,.top_ad_post,.top_ad_wrapper,.top_ads,.top_advert,.top_advertisement,.top_advertising_lb,.top_bar_ad,.top_container_ad,.topad,.topad-bar,.topadbox,.topads,.topadspot,.topadvertisementsegment,.topboardads,.topcontentadvertisement,.topic_inad,.topstoriesad,.toptenAdBoxA,.tourFeatureAd,.tower-ad,.towerAd,.towerAdLeft,.towerAds,.tower_ad,.tower_ad_disclaimer,.towerad,.tr-ad-adtech-placement,.tribal-ad,.ts-ad_unit_bigbox,.ts-banner_ad,.ttlAdsensel,.tto-sponsored-element,.tucadtext,.tvs-mpu,.twoColumnAd,.twoadcoll,.twoadcolr,.tx_smartadserver_pi1,.txt-ads,.txtAd,.txtAds,.txt_ads,.txtadvertise,.type_adscontainer,.type_miniad,.type_promoads,.ukAds,.ukn-banner-ads,.under_ads,.undertimyads,.unit-ad,.universalboxADVBOX01,.universalboxADVBOX03,.universalboxADVBOX04a,.usenext,.v5rc_336x280ad,.vert-ads,.vert-adsBlock,.vertad,.vertical-adsense,.vidadtext,.videoAd,.videoBoxAd,.video_ad,.view-promo-mpu-right,.view_rig_ad,.virgin-mpu,.wa_adsbottom,.wantads,.wide-ad,.wide-skyscraper-ad,.wideAd,.wideAdTable,.wide_ad,.wide_ad_unit_top,.wide_ads,.wide_google_ads,.widget-ad,.widget-ad-codes,.widget-ad300x250,.widget-entry-ads-160,.widgetYahooAds,.widget_ad,.widget_ad_boxes_widget,.widget_ad_rotator,.widget_advert_widget,.widget_econaabachoadswidget,.widget_island_ad,.widget_maxbannerads,.widget_sdac_bottom_ad_widget,.widget_sdac_footer_ads_widget,.widget_sdac_skyscraper_ad_widget,.wikia-ad,.wikia_ad_placeholder,.wingadblock,.withAds,.wl-ad,.wnMultiAd,.wp125_write_ads_widget,.wp125ad,.wp125ad_2,.wpn_ad_content,.wrap-ads,.wrapper-ad,.wrapper-ad-sidecol,.wsSponsoredLinksRight,.wsTopSposoredLinks,.x03-adunit,.x04-adunit,.x81_ad_detail,.xads-blk-top-hld,.xads-blk2,.xads-ojedn,.y-ads,.y-ads-wide,.y7-advertisement,.yahoo-sponsored,.yahoo-sponsored-links,.yahooAds,.yahoo_ads,.yahooad,.yahooad-image,.yahooad-urlline,.yan-sponsored,.ygrp-ad,.yom-ad,.youradhere,.yrail_ad_wrap,.yrail_ads,.ysmsponsor,.ysponsor,.yw-ad,.zRightAdNote,a[href^="http://ad-emea.doubleclick.net/"],a[href^="http://ad.doubleclick.net/"],a[href^="http://adserving.liveuniversenetwork.com/"],a[href^="http://galleries.pinballpublishernetwork.com/"],a[href^="http://galleries.securewebsiteaccess.com/"],a[href^="http://install.securewebsiteaccess.com/"],a[href^="http://latestdownloads.net/download.php?"],a[href^="http://secure.signup-page.com/"],a[href^="http://secure.signup-way.com/"],a[href^="http://www.FriendlyDuck.com/AF_"],a[href^="http://www.adbrite.com/mb/commerce/purchase_form.php?"],a[href^="http://www.firstload.de/affiliate/"],a[href^="http://www.friendlyduck.com/AF_"],a[href^="http://www.google.com/aclk?"],a[href^="http://www.liutilities.com/aff"],a[href^="http://www.liutilities.com/products/campaigns/adv/"],a[href^="http://www.my-dirty-hobby.com/?sub="],a[href^="http://www.ringtonematcher.com/"],#mclip_container:last-child,#ssmiwdiv[jsdisplay],#tads.c,#tadsb.c,.ch[onclick="ga(this,event)"],.ra[align="left"][width="30%"],.ra[align="right"][width="30%"],.rot_ads { display:none !important; }</style></html>