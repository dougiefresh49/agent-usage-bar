.PHONY: build app zip dmg release-artifacts verify-release install install-skill clean android-apk android-install

build:
	cd macos && swift build -c release --disable-keychain

app:
	bash macos/scripts/build.sh

zip:
	bash macos/scripts/build.sh --zip
	bash macos/scripts/verify-release.sh macos/AgentUsageBar.zip

dmg:
	bash macos/scripts/build.sh --dmg
	bash macos/scripts/verify-release.sh macos/AgentUsageBar.dmg

release-artifacts:
	bash macos/scripts/build.sh --zip --dmg
	bash macos/scripts/verify-release.sh macos/AgentUsageBar.zip
	bash macos/scripts/verify-release.sh macos/AgentUsageBar.dmg

verify-release:
	bash macos/scripts/verify-release.sh macos/AgentUsageBar.zip
	if [ -f macos/AgentUsageBar.dmg ]; then bash macos/scripts/verify-release.sh macos/AgentUsageBar.dmg; fi

install: app
	rm -rf /Applications/AgentUsageBar.app
	cp -R macos/AgentUsageBar.app /Applications/

install-skill:
	mkdir -p $(HOME)/.claude/skills
	rm -rf $(HOME)/.claude/skills/ai-usage
	cp -R skills/ai-usage $(HOME)/.claude/skills/ai-usage

android-apk:
	cd android && ./gradlew assembleDebug
	cp android/app/build/outputs/apk/debug/app-debug.apk android/AgentUsageBar-debug.apk

android-install: android-apk
	cd android && ./gradlew installDebug

clean:
	cd macos && swift package clean
	rm -rf macos/.xcode-widget-build macos/AgentUsageBar.app macos/AgentUsageBar.zip macos/AgentUsageBar.dmg
	cd android && ./gradlew clean || true
	rm -f android/AgentUsageBar-debug.apk
