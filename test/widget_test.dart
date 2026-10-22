import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mibandapp/ui/widgets/step_gauge.dart';
import 'package:mibandapp/ui/widgets/metric_card.dart';

void main() {
  testWidgets('StepGauge widget renders step count and distance', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StepGauge(
            steps: 7500,
            goal: 10000,
            calories: 320,
            distanceKm: 5.2,
          ),
        ),
      ),
    );

    expect(find.text('7500'), findsOneWidget);
    expect(find.text('Meta: 10000 passos (75%)'), findsOneWidget);
    expect(find.text('320'), findsOneWidget);
    expect(find.text('5.20'), findsOneWidget);
  });

  testWidgets('MetricCard widget renders BPM value and unit', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MetricCard(
            icon: Icons.favorite,
            iconColor: Colors.red,
            title: 'Frequência Cardíaca',
            value: '72',
            unit: 'BPM',
          ),
        ),
      ),
    );

    expect(find.text('Frequência Cardíaca'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
  });
}
