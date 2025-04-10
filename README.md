> [!IMPORTANT]  
> This is an experimental project that allows Torizon Cloud to be used with
> apt-based systems (Debian and Ubuntu).

This is an experimental project that allows Torizon Cloud to be used with
apt-based systems (Debian and Ubuntu).

Currently supported distributions: Debian {Stable (bookworm), Oldstable
(bullseye)} and Ubuntu {Noble (24.04), Jammy (22.04), Focal (20.04)}.

The script is tested against a fresh install of those distributions.

> [!WARNING]  
> Note that this script will permanently remove and install things in your system, so we do not recommend running it on development machines.
> Using a fresh, clean install, preferably that can be reset to a good and known state, is recommended for evaluating this solution.

To install, [create a Torizon Cloud account](https://app.torizon.io/run) and
run it as root (or with sudo):

```
sh -c "$(curl -sSL https://raw.githubusercontent.com/torizon/torizon-plugin-installer/main/install-torizon-plugin.sh)"
```

Or

```
sudo sh -c "$(curl -sSL https://raw.githubusercontent.com/torizon/torizon-plugin-installer/main/install-torizon-plugin.sh)"
```

The script will create a log file in `/tmp/install-torizon-plugin.log`.
