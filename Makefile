APP = HatchetBar.app

build:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/HatchetBar $(APP)/Contents/MacOS/
	cp Info.plist $(APP)/Contents/
	mkdir -p $(APP)/Contents/Resources
	cp -R .build/release/HatchetBar_HatchetBar.bundle $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

run: build
	open $(APP)

clean:
	rm -rf .build $(APP)

.PHONY: build run clean
