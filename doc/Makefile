# This is a Makefile that will render markdown or other source files (*.txt)
# in the current directory to html5 files in the DESTDIR.
# It will create also a basic index file as DESTDIR/index.html.
#
# Depends on pandoc <http://johnmacfarlane.net/pandoc>.
# TODO: add a template so it's a bit prettier.

SITE := $(shell basename `pwd`)
HEADER="<!DOCTYPE html><html><head><title>$(SITE)</title></head><body><ol>"
FOOTER="</ol></body></html>"

DESTDIR		?=$(HOME)/www/$(SITE)

OUTPUT := html5
PFLAGS += -s 

.SUFFIXES: .txt .html
SRCS := $(wildcard *.txt)

.txt.html:
	pandoc $(PFLAGS) -t $(OUTPUT) $*.txt -o $(DESTDIR)/$*.html
	@echo "<li><a href=\"$*.html\">$*</a></li>" >> $(DESTDIR)/index.html

.PHONY: all clean default

default: all

srcs: $(SRCS:.txt=.html)

mkdir:
	@mkdir -p $(DESTDIR)

mkindex:
	@echo $(HEADER) > $(DESTDIR)/index.html

footer:
	@echo $(FOOTER) >> $(DESTDIR)/index.html

all: mkdir mkindex srcs footer

clean:
	@- $(RM) $(DESTDIR)/*.html


