.PHONY: build app run zip dmg release-artifacts release verify-release install clean

build:
	cd macos && swift build -c release

app:
	bash macos/scripts/build.sh

run: app
	-pkill -x UsageKit
	open macos/UsageKit.app

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

release: release-artifacts
	@VERSION=$$(git tag -l 'v[0-9]*' --sort=-v:refname | head -1 | sed 's/v//'); \
	NEXT=$$(echo $${VERSION:-0.0.0} | awk -F. '{print $$1"."$$2"."$$3+1}'); \
	echo "Creating release v$$NEXT..."; \
	gh release create "v$$NEXT" macos/UsageKit.zip macos/UsageKit.dmg --generate-notes --target main

verify-release:
	bash macos/scripts/verify-release.sh macos/UsageKit.zip
	if [ -f macos/UsageKit.dmg ]; then bash macos/scripts/verify-release.sh macos/UsageKit.dmg; fi

install: app
	rm -rf /Applications/UsageKit.app
	cp -R macos/UsageKit.app /Applications/

clean:
	cd macos && swift package clean
	rm -rf macos/UsageKit.app macos/UsageKit.zip macos/UsageKit.dmg
