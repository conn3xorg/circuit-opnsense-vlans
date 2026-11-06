terraform {
  required_providers {
    # Pinned exactly: a new provider release is a reviewed change to this
    # circuit, tested against OPNsense before it's tagged.
    opnsense = {
      source  = "browningluke/opnsense"
      version = "0.26.0"
    }
  }
}
