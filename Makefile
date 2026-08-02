PASMO ?= pasmo
PYTHON ?= python3
BUILD_DIR := build
RELEASE_TAP := $(BUILD_DIR)/CooperRun.tap

.PHONY: all clean verify verify-bin

all: $(RELEASE_TAP)

$(BUILD_DIR)/cooper.bin: src/cooper.asm
	mkdir -p $(BUILD_DIR)
	$(PASMO) src/cooper.asm $(BUILD_DIR)/cooper.bin $(BUILD_DIR)/cooper.sym

$(RELEASE_TAP): $(BUILD_DIR)/cooper.bin assets/basic_loader.bin assets/loading_screen.scr tools/build_tap.py
	$(PYTHON) tools/build_tap.py \
		--loader assets/basic_loader.bin \
		--screen assets/loading_screen.scr \
		--code $(BUILD_DIR)/cooper.bin \
		--output $(RELEASE_TAP)

verify-bin: $(BUILD_DIR)/cooper.bin
	cmp $(BUILD_DIR)/cooper.bin release/CooperRun.bin
	@echo "Compiled binary matches the v1.0 release binary."

verify: $(RELEASE_TAP)
	cmp $(RELEASE_TAP) release/CooperRun.tap
	sha256sum $(RELEASE_TAP)
	@echo "Rebuilt TAP matches the v1.0 release exactly."

clean:
	rm -rf $(BUILD_DIR)
