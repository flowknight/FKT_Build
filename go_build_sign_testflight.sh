#!/bin/sh

KEYCHAIN_LIST=`security list-keychain | tr '\"' " " | tr "\n" " " | tr -s " "`

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
	echo ""
	echo "********************************************************"
	echo "*          Trapped CTRL-C, restoring keychaints        *"
	echo "********************************************************"
	
	security -v list-keychain -s `echo $KEYCHAIN_LIST`
	security -v list-keychain
	
	exit
}


# TODO: release notes

RELEASE_NOTES="TODO: grep something from git commit message"

WORKSPACE="Pexeso.xcworkspace"
SCHEME="Pexeso"

DEVELOPER_NAME="iPhone Distribution: FlowKnight s.r.o. (R4HTZ7RMVN)"
PROFILE_NAME="Pexeso_adhoc" # without extension
APP_NAME="Pexeso" # .app name (Packaging - Product Name in XCode)

TESTFLIGHT_API_TOKEN=""
TESTFLIGHT_TEAM_TOKEN=""
TESTFLIGHT_LIST="Inhouse" # list of people on testflight that will have immediate access upon build upload
TESTFLIGHT_NOTIFY="True" # True of False

APPLE_CER="scripts/certs/apple.cer"
DEVELOPER_CER="scripts/certs/dist.cer"
DEVELOPER_KEY="scripts/certs/dist.p12"
DEVELOPER_KEY_PASSWORD="" # leave as is for empty password

PROVISIONING_PROFILE="scripts/profile/$PROFILE_NAME.mobileprovision" # profile made with corresponding $DEVELOPER_CER

if [ ! -d "$WORKSPACE" ]; then
  echo "$WORKSPACE not found!"
  exit
fi

if [ ! -f "$APPLE_CER" ]; then
  echo "$APPLE_CER not found!"
  exit
fi

if [ ! -f "$DEVELOPER_CER" ]; then
  echo "$DEVELOPER_CER not found!"
  exit
fi

if [ ! -f "$DEVELOPER_KEY" ]; then
  echo "$DEVELOPER_KEY not found!"
  exit
fi

if [ ! -f "$PROVISIONING_PROFILE" ]; then
  echo "$PROVISIONING_PROFILE not found!"
  exit
fi

echo "********************************************************"
echo "*          Initial cleanup and setup                   *"
echo "********************************************************"
rm -rf Build DerivedData
git submodule update --init
pod install

echo "********************************************************"
echo "*          Creating temp keychain                      *"
echo "********************************************************"
KEYCHAIN_NAME="ios-build"
KEYCHAIN_PATH=~/Library/Keychains/ios-build.keychain
KEYCHAIN_PASSWORD=`whoami` # temporary keychain only, does not really matter

security -v create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security -v import "$APPLE_CER" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign
security -v import "$DEVELOPER_CER" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign
security -v import "$DEVELOPER_KEY" -k "$KEYCHAIN_PATH" -P "$DEVELOPER_KEY_PASSWORD" -T /usr/bin/codesign

# security -v default-keychain -d user -s "$KEYCHAIN_PATH"
security -v list-keychain -s "$KEYCHAIN_PATH"
security -v unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security -v set-keychain-settings -lut 7200 "$KEYCHAIN_PATH"

OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH" # I do not think this is necessary

mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
cp "$PROVISIONING_PROFILE" ~/Library/MobileDevice/Provisioning\ Profiles/

echo "********************************************************"
echo "*          Building...                                 *"
echo "********************************************************"
xctool -workspace "$WORKSPACE" -scheme "$SCHEME" -sdk iphoneos -configuration Release ONLY_ACTIVE_ARCH=NO

# sign
RELEASE_DATE=`date '+%Y-%m-%d %H:%M:%S'`
OUTPUTDIR="$PWD/Build/Products/Release-iphoneos"

echo "********************************************************"
echo "*          Signing                                     *"
echo "********************************************************"
xcrun -log -sdk iphoneos PackageApplication "$OUTPUTDIR/$APP_NAME.app" -o "$OUTPUTDIR/$APP_NAME.ipa" -sign "$DEVELOPER_NAME" -embed "$PROVISIONING_PROFILE"

echo "********************************************************"
echo "*          Deleting temp keychain                      *"
echo "********************************************************"
security -v delete-keychain "$KEYCHAIN_PATH"
rm -f ~/Library/MobileDevice/Provisioning\ Profiles/"$PROFILE_NAME".mobileprovision

# this has replaced with keychains from security framework listing
# KEYCHAIN_LIST=`find ~/Library/Keychains -name "*.keychain*" -exec echo {} \; | tr "\n" " "`
security -v list-keychain -s `echo $KEYCHAIN_LIST`
security -v list-keychain
 
echo "********************************************************"
echo "*          Zipping .dSYM                               *"
echo "********************************************************"
zip -r -9 "$OUTPUTDIR/$APP_NAME.app.dSYM.zip" "$OUTPUTDIR/$APP_NAME.app.dSYM"
 
CURL_LOGFILE="curl.log"
 
echo "********************************************************"
echo "*          Uploading                                   *"
echo "********************************************************"
curl http://testflightapp.com/api/builds.json \
  -o "$CURL_LOGFILE" \
  -F file="@$OUTPUTDIR/$APP_NAME.ipa" \
  -F dsym="@$OUTPUTDIR/$APP_NAME.app.dSYM.zip" \
  -F api_token="$TESTFLIGHT_API_TOKEN" \
  -F team_token="$TESTFLIGHT_TEAM_TOKEN" \
  -F distribution_lists="$TESTFLIGHT_LIST" \
  -F notify="$TESTFLIGHT_NOTIFY" \
  -F notes="$RELEASE_NOTES"

cat "$CURL_LOGFILE"
rm "$CURL_LOGFILE"

echo "********************************************************"
echo "*          Done                                        *"
echo "********************************************************"
