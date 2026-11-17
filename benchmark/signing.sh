# Uses the team set for the example in example/ios/Flutter/Team.xcconfig.
if [ ! -f ../example/ios/Flutter/Team.xcconfig ]; then
  echo "Create example/ios/Flutter/Team.xcconfig with DEVELOPMENT_TEAM=YOUR_TEAM_ID first." >&2
  exit 1
fi
cp ../example/ios/Flutter/Team.xcconfig ios/Flutter/Team.xcconfig
