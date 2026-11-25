# swiftbar-aws-vpn

[SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that shows your AWS Client VPN connection in the menu bar and switches between profiles.

## Requirements

* AWS VPN Client 6.0 or later
* SwiftBar: `brew install --cask swiftbar`

## Install

Download `aws-vpn.10s.sh` into your SwiftBar plugin folder and make it executable:

```sh
curl -fsSL https://raw.githubusercontent.com/reobin/swiftbar-aws-vpn/main/aws-vpn.10s.sh \
  -o "<your SwiftBar plugin folder>/aws-vpn.10s.sh"
chmod +x "<your SwiftBar plugin folder>/aws-vpn.10s.sh"
```

## License

MIT
