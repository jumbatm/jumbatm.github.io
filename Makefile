# Build configuration.
URL=$(shell pwd) # URL here.
BUILD_DIR=build
EXT=html
FOOTER=footer.md
HEADER=header.md
PANDOC=pandoc --self-contained -f markdown -c "style.css"
PUBLISH_BRANCH=build

IGNORE=$(HEADER) $(FOOTER)

# Specify directories to generate a corresponding file with all files.
LISTINGS = posts

MDFILES = $(shell find . -name '*.md' $(addprefix -not -name , $(HEADER)))
ADDITIONAL_FILES=style.css
LISTINGS_FILES=$(addprefix $(BUILD_DIR)/, $(addsuffix .$(EXT),$(LISTINGS)))
# Generate links to each of these files at the top of the page.
HEADERS=$(shell ls '*.md')

OUTPUT = $(addprefix $(BUILD_DIR)/, $(patsubst %.md,%.$(EXT),$(MDFILES)) $(ADDITIONAL_FILES))

all: $(OUTPUT) $(LISTINGS_FILES)

# Generate the final file from the preprocessed markdown.
$(BUILD_DIR)/%.$(EXT): $(BUILD_DIR)/%.md
	mkdir -p $(BUILD_DIR)/$(dir $<)
	$(PANDOC) -o $@  $<

# Add the header and footer to the file.
$(BUILD_DIR)/%.md: %.md
	mkdir -p $(BUILD_DIR)/$(dir $<)
	cat $(HEADER) >>$@
	echo >>$@
	cat $< >>$@
	echo >>$@
	cat $(FOOTER) >>$@

# Listings files are generated in the same way.
$(BUILD_DIR)/%.$(EXT): $(BUILD_DIR)/%.listing.md
	mkdir -p $(BUILD_DIR)/$(dir $<)
	$(PANDOC) -o $@  $<

$(BUILD_DIR)/%: %
	cp $< $@

$(BUILD_DIR):
	mkdir -p $@

# Generate listings files from directory targets.
$(BUILD_DIR)/%.listing.md: %
	echo "# $*" > $@
	cat $(HEADER) >>$@
	echo >>$@
	for f in $(shell cd $* && ls | sed -e 's/.md/.$(EXT)/g') ; do \
		echo "- [$$f]($*/$$f) " >> $@ ; \
	done
	echo >>$@
	cat $(FOOTER) >>$@

clean: clean_output
	$(shell find $(BUILD_DIR) -depth -exec rmdir {} \;)

clean_output:
	rm -f $(LISTINGS_FILES) $(OUTPUT)

publish: all
	git checkout $(PUBLISH_BRANCH)
	cp -r $(BUILD_DIR)/* .
	git add .
	git commit -m "Published."
	git checkout -

.PHONY: all clean clean_output listings publish
