SHELL := /bin/bash

RAWDATA ?= DEADBEEFRAW
INDEX   ?= DEADBEEFINDEX
CHUNK_PREFIX := data/CHUNK_
CHUNK_SUFFIX := _CHUNK
RAWDATA_LINES_PER_CHUNK ?= 300000
TESTDATA_LINES_PER_CHUNK ?= 7000

raw_data  := data/$(RAWDATA)
use_index := data/$(INDEX)
use_posting_dict := data/$(basename $(notdir $(use_index))).posting.dict

filtered_data      = $(raw_data).filtered
query_data         = $(raw_data).queries
build_index        = $(raw_data).index
build_posting_dict = $(raw_data).posting.dict
test_data          = $(raw_data).test_data
reordered_queries  = $(raw_data).reordered_queries
filtered_test_data = $(test_data).filtered
evaluation         = $(raw_data).eval
histogram          = $(raw_data).histogram

# target for checking that RAWDATA was specified and existed
$(raw_data):
ifeq ($(RAWDATA), DEADBEEFRAW)
	$(error RAWDATA not specified!)
endif
ifeq ($(wildcard $@),)
	$(error $@ does not exist!)
endif

$(use_index):
ifeq ($(INDEX), DEADBEEFINDEX)
	$(error INDEX not specified!)
endif
	$(MAKE) RAWDATA=$(basename $(notdir $@)) build_index

$(filtered_data): $(raw_data) programs/filterData.py
	split -l $(RAWDATA_LINES_PER_CHUNK) $< $(CHUNK_PREFIX)
	for i in $(CHUNK_PREFIX)*; do \
		cat $$i | python programs/filterData.py > $${i}$(CHUNK_SUFFIX) && rm -f $$i & \
	done; \
	wait
	rm -f $@
	for i in data/*$(CHUNK_SUFFIX); do \
	    cat $$i >> $@ && rm -f $$i; \
	done

$(build_index): $(filtered_data) programs/index_mapper.py programs/index_reducer.py
	cat $(filtered_data) | python programs/index_mapper.py | sort -k1n -k2n | python programs/index_reducer.py > $@ && mv posting.dict $(build_posting_dict)

$(query_data): $(filtered_data) programs/visitorQueryMapper.py programs/visitorQueryReducer.py
	cat $(filtered_data) | python programs/visitorQueryMapper.py | sort -k1,1n -k2,2 -k3,3 -k4,4 -k5,5n | python programs/visitorQueryReducer.py > $@

$(test_data): $(query_data) programs/testGen.py
	cat $(query_data) | python programs/testGen.py > $@

$(filtered_test_data): $(test_data) $(use_index) programs/filterTestData.py
	cat $< | python programs/filterTestData.py $(use_index) $(use_posting_dict) > $@

$(reordered_queries): $(filtered_test_data) $(use_index) programs/reRank.py
	split -l $(TESTDATA_LINES_PER_CHUNK) $< $(CHUNK_PREFIX)
	for i in $(CHUNK_PREFIX)*; do \
	    python programs/reRank.py --index $(use_index) --dict $(use_posting_dict) $$i > $${i}$(CHUNK_SUFFIX) && rm -f $$i & \
	done; \
	wait
	rm -f $@
	for i in data/*$(CHUNK_SUFFIX); do \
	    cat $$i >> $@ && rm -f $$i; \
	done

$(evaluation): $(reordered_queries) programs/evaluate.py
	cat $< | python programs/evaluate.py > $@

$(histogram): $(reordered_queries) programs/eval_mapper.py programs/eval_reducer.py
	cat $< | python programs/eval_mapper.py | python programs/eval_reducer.py > $@

# filter out "bad" data (malformed JSON, missing columns, etc.)
filter_data : $(filtered_data) 

# group pageviews into whole queries
query_data : $(query_data)

# build the index and posting.dict for RAWDATA
build_index : $(build_index)

# filter out queries our algorithm won't impact
filter_test_data : $(filtered_test_data)

# re-rank query results
reorder_queries : $(reordered_queries)

# compute evaluation metric(s)
evaluate : $(evaluation)

# generate additional stats
histogram : $(histogram)

# Here we make empty targets for each program so that make can tell when a program
# has been modified and needs to rebuild a target
programs = filterData.py index_mapper.py index_reducer.py\
           visitorQueryMapper.py visitorQueryReducer.py testGen.py\
           filterTestData.py reRank.py evaluate.py eval_mapper.py eval_reducer.py

$(addprefix programs/, $(programs)):

clean : $(raw_data)
	rm -f $(raw_data).* ${CHUNK_PREFIX}* data/*${CHUNK_SUFFIX}

.PHONY : clean build_index filter_data query_data reorder_queries evaluate histogram filter_test_data
