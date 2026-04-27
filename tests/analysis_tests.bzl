"""Analysis-time tests. Verify rules instantiate cleanly and expose
DefaultInfo without needing kubectl / a real cluster."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_certmanager//:defs.bzl", "cert_manager_health_check", "cert_manager_install")

def _has_executable_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(
        env,
        target[DefaultInfo].files_to_run.executable != None,
        "expected target to expose an executable",
    )
    return analysistest.end(env)

_has_executable_test = analysistest.make(_has_executable_impl)

def cert_manager_install_test_suite(name):
    cert_manager_install(name = name + "_subject", tags = ["manual"])
    _has_executable_test(name = name + "_executable", target_under_test = ":" + name + "_subject")
    native.test_suite(name = name, tests = [":" + name + "_executable"])

def cert_manager_health_check_test_suite(name):
    cert_manager_health_check(name = name + "_subject", tags = ["manual"])
    _has_executable_test(name = name + "_executable", target_under_test = ":" + name + "_subject")
    native.test_suite(name = name, tests = [":" + name + "_executable"])
