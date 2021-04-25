documentation:
	rm -rf docs
	jazzy --no-hide-documentation-coverage --module Scyther --swift-build-tool xcodebuild --build-tool-arguments -scheme,Scyther,-sdk,iphoneos