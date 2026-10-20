.PHONY: build run security-check package clean diagnose smoke benchmark
build:
	swift build
run: package
	open dist/LogiMXLite.app

security-check:
	bash scripts/security-check.sh
package:
	./scripts/package.sh
diagnose: build
	swift run --skip-build LogiMXLite --diagnose
smoke: package
	./dist/LogiMXLite.app/Contents/MacOS/LogiMXLite --smoke-test
benchmark: package
	/usr/bin/time -l ./dist/LogiMXLite.app/Contents/MacOS/LogiMXLite --stress-benchmark 100000000
clean:
	swift package clean
	rm -rf dist/LogiMXLite.app
