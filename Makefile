#
# Please specify your Emacs here.
#
EMACS	= emacs
# To install Wanderlust for XEmacs 21 or later,
# running 'make install-package' is recommended.
# 'make install-package' refers $XEMACS instead of $EMACS.
XEMACS  = xemacs
#
# Target directory to install the Wanderlust package.
# (Automatically detected if this line is unchanged.)
#
LISPDIR = NONE
#LISPDIR = /usr/local/lib/mule/site-lisp

INFODIR = NONE
#INFODIR = /usr/local/share/info

# For XEmacs package.
PACKAGEDIR = NONE

# For XEmacs or Emacs 21: directory where icon files should go.
PIXMAPDIR = NONE


################# No need to modify following lines ####################
FLAGS   = -batch -q -no-site-file

elc:
	$(EMACS) $(FLAGS) -l WL-MK -f compile-wl-package $(LISPDIR) $(PIXMAPDIR)

install-elc:
	$(EMACS) $(FLAGS) -l WL-MK -f install-wl-package $(LISPDIR) $(PIXMAPDIR)

uninstall-elc:
	$(EMACS) $(FLAGS) -l WL-MK -f uninstall-wl-package $(LISPDIR) $(PIXMAPDIR)

clean-elc:
	rm -f wl/*.elc wl/auto-autoloads.el wl/custom-load.el elmo/*.elc utils/*.elc utils/hmac/lisp/*.elc

package:
	$(XEMACS) $(FLAGS) -l WL-MK -f compile-wl-package-xmas $(PACKAGEDIR) $(PIXMAPDIR)

install-package:
	$(XEMACS) $(FLAGS) -l WL-MK -f install-wl-package-xmas $(PACKAGEDIR) $(PIXMAPDIR)

info:
	$(EMACS) $(FLAGS) -l WL-MK -f wl-texinfo-format $(INFODIR)

install-info:
	$(EMACS) $(FLAGS) -l WL-MK -f install-wl-info $(INFODIR)

all: elc

install: install-elc

uninstall: uninstall-elc

clean: clean-elc
