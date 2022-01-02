documentation:
	rm -rf docs
	jazzy --module Scyther --swift-build-tool xcodebuild --build-tool-arguments -scheme,Scyther,-destination,generic/platform=iOS
