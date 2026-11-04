// Lists the texts of lib/ that are shown to people, as the keys of the language files (their Turkish wording).
// Texts with interpolation come out with {name} placeholders. Usage: dart run tool/extract_strings.dart [--json]
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class _V extends RecursiveAstVisitor<void> {
  final out = <String>{};
  bool _skip(AstNode n) {
    for (AstNode? p = n.parent; p != null; p = p.parent) {
      if (p is Directive || p is Annotation) return true;
      if (p is InstanceCreationExpression) {
        final t = p.constructorName.type.toString();
        if (const {'RegExp', 'File', 'Directory', 'Uri', 'Exception', 'ArgumentError', 'StateError'}.contains(t)) return true;
      }
      if (p is MethodInvocation) {
        final m = p.methodName.name;
        if (const {'File', 'Directory', 'RegExp', 'exec', 'script', 'contains', 'startsWith', 'endsWith', 'replaceAll', 'split', 'join', 'indexOf', 'pushNamed', 'pushReplacementNamed', 'rootBundle', 'loadString'}.contains(m)) return true;
      }
    }
    return false;
  }

  void _add(StringLiteral n) {
    if (_skip(n)) return;
    String s;
    if (n is StringInterpolation) {
      final b = StringBuffer();
      for (final e in n.elements) {
        if (e is InterpolationString) {
          b.write(e.value);
        } else if (e is InterpolationExpression) {
          final src = e.expression.toSource();
          b.write('{${src.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '')}}');
        }
      }
      s = b.toString();
    } else {
      s = n.stringValue ?? '';
    }
    s = s.trim();
    if (s.length < 3) return;
    final looksText = RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]{2,}').hasMatch(s) && (s.contains(' ') || RegExp(r'[ÇĞİÖŞÜçğıöşü]').hasMatch(s) || RegExp(r'^[A-ZÇĞİÖŞÜ][a-zçğıöşü]+$').hasMatch(s));
    if (!looksText) return;
    if (s.startsWith('http') || s.startsWith('assets/') || s.startsWith('package:') || s.contains(r'\') || s.startsWith('-')) return;
    out.add(s);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _add(node);
  @override
  void visitAdjacentStrings(AdjacentStrings node) => _add(node);
  @override
  void visitStringInterpolation(StringInterpolation node) {
    _add(node);
    // do not descend: nested literals inside the expressions are separate texts
    for (final e in node.elements) {
      if (e is InterpolationExpression) e.expression.accept(this);
    }
  }
}

void main(List<String> args) {
  final v = _V();
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    if (f.path.contains('l10n')) continue;
    parseString(content: f.readAsStringSync(), path: f.path, throwIfDiagnostics: false).unit.accept(v);
  }
  final list = v.out.toList()..sort();
  if (args.contains('--json')) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(list));
  } else {
    list.forEach(stdout.writeln);
  }
}
