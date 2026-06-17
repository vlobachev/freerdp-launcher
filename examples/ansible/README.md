# Example Ansible automation

A reference, **sanitized** version of the Ansible that provisions and configures
the GPU-accelerated GNOME-over-RDP container described in
[`../../docs/proxmox-ubuntu-gnome-rdp.md`](../../docs/proxmox-ubuntu-gnome-rdp.md).

These are **examples** — every site-specific value (IPs, MAC, username, GPU GIDs,
storage, node name, SSH key) lives in `vars.example.yml` as a `<PLACEHOLDER>`.
Copy it, fill it in, and point your inventory at your Proxmox host + the container.

## Files

- `vars.example.yml` — copy to `vars.yml` and edit.
- `provision-desktop-lxc.yml` — create the unprivileged LXC on the Proxmox host
  (features `fuse=1`, `lxc.apparmor.profile: unconfined`, `/dev/dri` passthrough).
- `desktop.yml` — install the Ubuntu desktop + `gnome-remote-desktop` + browsers,
  make gdm3 the DM, default the user to the `ubuntu` session, generate grd's TLS
  cert, bind RDP.

## Usage

```sh
cp vars.example.yml vars.yml      # then edit vars.yml

# inventory.yml must define your Proxmox host (group/alias `proxmox`) and the
# container host (`desktop`), both reachable over SSH as root, plus the var
# `provision_ssh_authorized_key` (your pubkey, injected into the new CT).

ansible-playbook -i inventory.yml provision-desktop-lxc.yml
ansible-playbook -i inventory.yml desktop.yml -l desktop \
  -e desktop_rdp_password='your-rdp-password'     # or set it manually after
```

Then connect with **FreeRDP Launcher**, codec **AVC420**, for GPU-accelerated GNOME.
