# Verification-command discovery.

# Discover the project test/lint command; empty if none found.
sr_test_cmd() {
  if   [ -f package.json ] && grep -q '"test"' package.json; then echo "npm test"
  elif [ -f Cargo.toml ]; then echo "cargo test"
  elif [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -f setup.cfg ]; then echo "pytest"
  fi
}
