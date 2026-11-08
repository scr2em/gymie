.PHONY: app run test install clean icon pose-server screenshots

app:            ## Build build/Gymie.app
	./scripts/build-app.sh

run: app        ## Build and launch (quits a running copy first)
	-pkill -x Gymie; sleep 0.5
	open build/Gymie.app

test:           ## Run the GymieCore tests
	swift test

install: app    ## Copy to ~/Applications (launch at login works best from there)
	mkdir -p ~/Applications
	-pkill -x Gymie; sleep 0.5
	rm -rf ~/Applications/Gymie.app
	cp -R build/Gymie.app ~/Applications/
	open ~/Applications/Gymie.app

pose-server:    ## One-time setup of the local pose engine (Python 3.10-3.12 + MediaPipe)
	./scripts/setup-pose-server.sh

screenshots: app ## Render docs/screenshots/*.png from the real views with demo data
	build/Gymie.app/Contents/MacOS/Gymie --snapshots "$(CURDIR)/docs/screenshots"

icon:           ## Regenerate Support/AppIcon.icns
	swift scripts/make-icon.swift Support

clean:
	rm -rf .build build
