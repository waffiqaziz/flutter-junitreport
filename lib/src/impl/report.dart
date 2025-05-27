// Copyright (c) 2017-2021, TOPdesk. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a MIT-style
// license that can be found in the LICENSE file.

import 'dart:math';

import 'package:intl/intl.dart';
import 'package:xml/xml.dart';
import 'package:testreport/testreport.dart';
import 'package:flutter_junitreport/flutter_junitreport.dart';
import 'package:flutter_junitreport/src/impl/xml.dart';

class XmlReport implements JUnitReport {
  static final NumberFormat _milliseconds = NumberFormat('#####0.00#', 'en_US');
  static final DateFormat _dateFormat =
      DateFormat('yyyy-MM-ddTHH:mm:ss', 'en_US');
  static final Pattern _pathSeparator = RegExp(r'[\\/]');
  static final Pattern _dash = RegExp(r'-');
  static const Map<String, dynamic> _noAttributes = <String, dynamic>{};
  static const Iterable<XmlNode> _noChildren = <XmlNode>[];

  final String base;
  final String package;

  XmlReport(this.base, this.package);

  @override
  String toXml(Report report) {
    final suites = <XmlNode>[];
    for (final suite in report.suites) {
      final cases = <XmlNode>[];
      final prints = <XmlNode>[];
      final className = _pathToClassName(suite.path);

      for (final test in suite.allTests) {
        if (test.isHidden) {
          _prints(test.prints, prints);
          continue;
        }

        final children = <XmlNode>[];
        if (test.isSkipped) {
          children.add(elem('skipped', _noAttributes, _noChildren));
        }
        if (test.problems.isNotEmpty) {
          children.add(_problems(test.problems));
        }

        _prints(test.prints, children);

        cases.add(elem(
            'testcase',
            <String, dynamic>{
              'classname': className,
              'name': test.name,
              'time': _milliseconds.format(test.duration / 1000.0)
            },
            children));
      }
      final attributes = <String, dynamic>{
        'errors': suite.problems
            .where((t) => !t.problems.every((p) => p.isFailure))
            .length,
        'failures': suite.problems
            .where((t) => t.problems.every((p) => p.isFailure))
            .length,
        'tests': suite.tests.length,
        'skipped': suite.skipped.length,
        'name': className
      };
      if (report.timestamp != null) {
        attributes['timestamp'] = _dateFormat.format(report.timestamp!.toUtc());
      }
      suites.add(elem('testsuite', attributes,
          _suiteChildren(suite.platform, cases, prints)));
    }
    return toXmlString(doc([elem('testsuites', _noAttributes, suites)]));
  }

  String _pathToClassName(String path) {
    String main;
    if (path.endsWith('_test.dart')) {
      main = path.substring(0, path.length - '_test.dart'.length);
    } else if (path.endsWith('.dart')) {
      main = path.substring(0, path.length - '.dart'.length);
    } else {
      main = path;
    }

    path = path.replaceAll('\\', '/');

    if (base.isNotEmpty && main.startsWith(base)) {
      main = main.substring(base.length);
      while (main.startsWith(_pathSeparator)) {
        main = main.substring(1);
      }
    }

    // Strip bas path until the 'test' directory
    var splits = path.split('/');
    var testIdx = max(0, splits.indexOf('test'));

    return splits
        .sublist(testIdx)
        .join('/')
        .replaceAll(_pathSeparator, '.')
        .replaceAll(_dash, '_');
  }

  List<XmlNode> _suiteChildren(
    String? platform,
    Iterable<XmlNode> cases,
    Iterable<XmlNode> prints,
  ) =>
      <XmlNode>[
        ..._properties(platform),
        ...cases,
        ...prints,
      ];

  void _prints(Iterable<String> from, List<XmlNode> to) {
    if (from.isNotEmpty) {
      to.add(
          elem('system-out', _noAttributes, <XmlNode>[txt(from.join('\n'))]));
    }
  }

  List<XmlElement> _properties(String? platform) => platform == null
      ? []
      : [
          elem('properties', _noAttributes, <XmlNode>[
            elem(
                'property',
                <String, dynamic>{'name': 'platform', 'value': platform},
                _noChildren)
          ])
        ];

  XmlElement _problems(Iterable<Problem> problems) {
    if (problems.length == 1) {
      final problem = problems.first;
      final message = problem.message;
      if (!message.contains('\n')) {
        final stacktrace = problem.stacktrace;
        return elem(
            problem.isFailure ? 'failure' : 'error',
            <String, dynamic>{'message': message},
            stacktrace.isEmpty ? _noChildren : <XmlNode>[txt(stacktrace)]);
      }
    }

    final failures = problems.where((p) => p.isFailure);
    final errors = problems.where((p) => !p.isFailure);
    final details = <String>[
      ..._details(failures),
      ..._details(errors),
    ];

    var type = errors.isEmpty ? 'failure' : 'error';
    return elem(
        type,
        <String, dynamic>{'message': _message(failures.length, errors.length)},
        <XmlNode>[txt(details.join(r'\n\n\n'))]);
  }

  Iterable<String> _details(Iterable<Problem> problems) {
    final more = problems.length > 1;
    var count = 0;
    return problems.map((p) => _report(more, ++count, p));
  }

  String _report(bool more, int index, Problem problem) {
    final message = problem.message;
    var stacktrace = problem.stacktrace;
    var short = '';
    String? long;
    if (message.isEmpty) {
      if (stacktrace.isEmpty) short = ' no details available';
    } else if (!message.contains('\n')) {
      short = ' $message';
    } else {
      long = message;
    }
    if (message.isNotEmpty && problem.isFailure) stacktrace = '';

    final report = <String>[];
    final type = problem.isFailure ? 'Failure' : 'Error';
    if (more) {
      report.add('$type #$index:$short');
    } else {
      report.add('$type:$short');
    }
    if (long != null) report.add(long);
    if (stacktrace.isNotEmpty) report.add('Stacktrace:\n$stacktrace');
    return report.join('\n\n');
  }

  String _message(int failures, int errors) {
    final texts = <String>[];
    if (failures == 1) texts.add('1 failure');
    if (failures > 1) texts.add('$failures failures');
    if (errors == 1) texts.add('1 error');
    if (errors > 1) texts.add('$errors errors');
    texts.add('see stacktrace for details');
    return texts.join(', ');
  }
}
