.PHONY: build app zip dmg release-artifacts verify-release install clean

build:
	cd macos && swift build -c release

app:
	bash macos/scripts/build.sh

zip:
	bash macos/scripts/build.sh --zip
	bash macos/scripts/verify-release.sh macos/UsageKit.zip

dmg:
	bash macos/scripts/build.sh --dmg
	bash macos/scripts/verify-release.sh macos/UsageKit.dmg

release-artifacts:
	bash macos/scripts/build.sh --zip --dmg
	bash macos/scripts/verify-release.sh macos/UsageKit.zip
	bash macos/scripts/verify-release.sh macos/UsageKit.dmg

verify-release:
	bash macos/scripts/verify-release.sh macos/UsageKit.zip
	if [ -f macos/UsageKit.dmg ]; then bash macos/scripts/verify-release.sh macos/UsageKit.dmg; fi

install: app
	rm -rf /Applications/UsageKit.app
	cp -R macos/UsageKit.app /Applications/

clean:
	cd macos && swift package clean
	rm -rf macos/UsageKit.app macos/UsageKit.zip macos/UsageKit.dmg
