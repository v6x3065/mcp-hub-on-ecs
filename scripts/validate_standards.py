#!/usr/bin/env python3
"""Validate aws-mcp CloudFormation templates against the project standards.

Usage: python scripts/validate_standards.py [template.yaml ...]
Without arguments every template under templates/ is checked.
Exit code 1 if any rule is violated.
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "templates"
NAME_RE = re.compile(r"^lly-nw-cloudops-awsmcp(-[a-z]+(-[a-z]+)*)?-[dqp]-[a-z]+-\d{2}$")
IMPORT_RE = re.compile(r"^\$\{(?P<param>\w+)\}:(?P<output>\w+)$")


def _construct(loader, suffix, node):
    key = suffix if suffix in ("Ref", "Condition") else f"Fn::{suffix}"
    if isinstance(node, yaml.ScalarNode):
        value = loader.construct_scalar(node)
    elif isinstance(node, yaml.SequenceNode):
        value = loader.construct_sequence(node, deep=True)
    else:
        value = loader.construct_mapping(node, deep=True)
    return {key: value}


class CfnLoader(yaml.SafeLoader):
    pass


CfnLoader.add_multi_constructor("!", _construct)


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.load(f, Loader=CfnLoader)


def walk(node):
    yield node
    if isinstance(node, dict):
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)


def check_template(path, tags, errors):
    def err(msg):
        errors.append(f"{path.relative_to(ROOT)}: {msg}")

    stem = path.stem
    if " " in str(path):
        err("path must not contain spaces")
    if not NAME_RE.match(stem):
        err(f"file name '{stem}' does not match the naming standard")

    tpl = load(path)
    params = tpl.get("Parameters", {})

    for name, spec in params.items():
        default = spec.get("Default")
        if default is None or str(default).strip() == "":
            err(f"parameter {name} has an empty/missing Default (CI turns it into 'default_placeholder')")

    for pname, spec in tags.items():
        if pname not in params:
            err(f"missing tag parameter {pname}")
        elif str(params[pname].get("Default")) != spec["default"]:
            err(f"{pname} Default '{params[pname].get('Default')}' != standard '{spec['default']}'")

    defaults = {str(p.get("Default")) for p in params.values()}
    if stem not in defaults and f"/{stem}" not in {d[d.rfind("/"):] for d in defaults if "/" in d}:
        err("no parameter Default equals the file name (resource name must equal the file name)")

    expected_keys = {"Name"} | {spec["key"] for spec in tags.values()}
    for rid, res in tpl.get("Resources", {}).items():
        props = res.get("Properties", {})
        rtags = props.get("Tags")
        if isinstance(rtags, list):
            keys = {t.get("Key") for t in rtags if isinstance(t, dict)}
            if expected_keys - keys:
                err(f"resource {rid} is missing tags: {sorted(expected_keys - keys)}")
        if res.get("Type") == "AWS::IAM::Role" and "PermissionsBoundary" not in props:
            err(f"IAM role {rid} has no PermissionsBoundary")

    for oid, out in tpl.get("Outputs", {}).items():
        if oid == "StackContact":
            continue
        export = (out.get("Export") or {}).get("Name")
        if export != {"Fn::Sub": f"${{AWS::StackName}}:{oid}"}:
            err(f"output {oid} must export '${{AWS::StackName}}:{oid}'")

    for node in walk(tpl):
        if not (isinstance(node, dict) and "Fn::ImportValue" in node):
            continue
        sub = node["Fn::ImportValue"]
        sub = sub.get("Fn::Sub") if isinstance(sub, dict) else None
        m = IMPORT_RE.match(sub or "")
        if not m:
            err(f"ImportValue must be !Sub '${{pXxxStackName}}:<Output>', got {sub!r}")
            continue
        param, output = m.group("param"), m.group("output")
        if param not in params:
            err(f"ImportValue uses undefined parameter {param}")
            continue
        upstream = str(params[param].get("Default"))
        files = list(TEMPLATES.rglob(f"{upstream}.yaml"))
        if not files:
            err(f"{param} Default '{upstream}' has no template under templates/")
        elif output not in load(files[0]).get("Outputs", {}):
            err(f"upstream {upstream} does not define output {output}")


def main(argv):
    tags = load(ROOT / "standards" / "tags.yaml")["tags"]
    files = [Path(a).resolve() for a in argv] or sorted(TEMPLATES.rglob("*.yaml"))
    errors = []
    for f in files:
        check_template(f, tags, errors)
    for e in errors:
        print(f"ERROR {e}")
    print(f"{len(files)} template(s) checked, {len(errors)} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
