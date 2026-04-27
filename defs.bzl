"""Public API for rules_certmanager."""

load("//private:cert_manager_health_check.bzl", _cert_manager_health_check = "cert_manager_health_check")
load("//private:cert_manager_install.bzl", _cert_manager_install = "cert_manager_install")
load("//private:providers.bzl", _CertManagerInfo = "CertManagerInfo")

cert_manager_install = _cert_manager_install
cert_manager_health_check = _cert_manager_health_check

CertManagerInfo = _CertManagerInfo
