# Sparkle Auto-Update Setup

## Generate EdDSA keys

After building Notero with Sparkle, generate keys for signing updates:

```bash
# Find generate_keys in DerivedData
find ~/Library/Developer/Xcode/DerivedData -name "generate_keys" -path "*/Sparkle/*" 2>/dev/null | head -1

# Run it (use the path from above)
/path/to/generate_keys
```

This will:
1. Generate a new EdDSA key pair
2. Store the private key in your Keychain
3. Print the **public key** — add it to `project.yml` as `SUPublicEDKey`

## Appcast

Host your appcast at `https://danielgamrot.cz/notero/appcast.xml`.

## Signing updates

```bash
# Find sign_update in DerivedData
find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/Sparkle/*" 2>/dev/null | head -1

# Sign the DMG/ZIP
/path/to/sign_update Notero-1.0.zip
```

Copy the output `edSignature` and `length` into your appcast XML.
