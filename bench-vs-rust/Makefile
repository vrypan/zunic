COMPARISONS := rust-linebreak rust-normalize rust-words rust-wrap rust-width
PYTHON ?= python3

.DEFAULT_GOAL := all
.NOTPARALLEL:
.PHONY: all build test bench report clean $(COMPARISONS)

all: test

build bench:
	@for comparison in $(COMPARISONS); do \
		$(MAKE) -C $$comparison $@ || exit $$?; \
	done

test:
	$(PYTHON) test_build_inputs.py
	$(PYTHON) test_benchmark_contract.py
	$(PYTHON) test_benchmark_table.py
	$(PYTHON) test_benchmark_report.py
	$(PYTHON) test_benchmark_progress.py
	@for comparison in $(COMPARISONS); do \
		$(MAKE) -C $$comparison test || exit $$?; \
	done
	$(PYTHON) test_executable_cli.py

report:
	@test -n "$(SUMMARY)" || { echo "usage: make report SUMMARY=path/to/summary.json" >&2; exit 2; }
	$(PYTHON) benchmark_report.py $(SUMMARY)

# Run one folder directly, for example: make rust-words TARGET=bench PAIRS=1
TARGET ?= all
$(COMPARISONS):
	$(MAKE) -C $@ $(TARGET)

clean:
	@for comparison in $(COMPARISONS); do \
		$(MAKE) -C $$comparison clean || exit $$?; \
	done
	rm -rf __pycache__
