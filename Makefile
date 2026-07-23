.PHONY: build app zip dmg release-artifacts verify-release install install-skill clean

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

clean:
	cd macos && swift package clean
	rm -rf macos/AgentUsageBar.app macos/AgentUsageBar.zip macos/AgentUsageBar.dmg
