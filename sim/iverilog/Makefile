RTL_DIR = ../../rtl
MAPPERS_DIR = $(RTL_DIR)/mappers

IVERILOG = iverilog
VVP = vvp

# Source files
MBC2_SRC = $(MAPPERS_DIR)/mbc2.v
DPRAM_SRC = dpram.v
HARNESS_SRC = mbc2_cram_harness.v

.PHONY: all test test_standalone test_cram test_cram_unfixed clean

all: test

# Run all tests (fixed)
test: test_standalone test_cram
	@echo ""
	@echo "========================================="
	@echo "  All test suites completed successfully"
	@echo "========================================="

# Test 1: MBC2 register logic (standalone)
test_standalone: mbc2_standalone
	@echo ""
	@echo "--- Running MBC2 standalone tests ---"
	$(VVP) mbc2_standalone

mbc2_standalone: mbc2_standalone_tb.v $(MBC2_SRC)
	$(IVERILOG) -o $@ -I$(MAPPERS_DIR) $^

# Test 2: CRAM write/read path WITH fix
test_cram: mbc2_cram_fixed
	@echo ""
	@echo "--- Running MBC2 CRAM tests (WITH fix) ---"
	$(VVP) mbc2_cram_fixed

mbc2_cram_fixed: mbc2_cram_tb.v $(HARNESS_SRC) $(DPRAM_SRC) $(MBC2_SRC)
	$(IVERILOG) -o $@ -DMBC2_WRITE_FIX -I$(MAPPERS_DIR) $^

# Test 3: CRAM write/read WITHOUT fix (discriminating test expected to fail)
test_cram_unfixed: mbc2_cram_unfixed
	@echo ""
	@echo "--- Running MBC2 CRAM tests (WITHOUT fix) ---"
	@echo "--- (discriminating test EXPECTED to fail) ---"
	-$(VVP) mbc2_cram_unfixed

mbc2_cram_unfixed: mbc2_cram_tb.v $(HARNESS_SRC) $(DPRAM_SRC) $(MBC2_SRC)
	$(IVERILOG) -o $@ -I$(MAPPERS_DIR) $^

clean:
	rm -f mbc2_standalone mbc2_cram_fixed mbc2_cram_unfixed
	rm -f *.vcd
