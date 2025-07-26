import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/responsive_service.dart';

class ResponsiveDataTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final bool sortAscending;
  final int? sortColumnIndex;
  final Function(int, bool)? onSort;

  const ResponsiveDataTable({
    Key? key,
    required this.columns,
    required this.rows,
    this.sortAscending = true,
    this.sortColumnIndex,
    this.onSort,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && ResponsiveService.isDesktop(context)) {
      return _buildWebTable(context);
    } else if (ResponsiveService.isTablet(context)) {
      return _buildTabletTable(context);
    } else {
      return _buildMobileCards(context);
    }
  }

  Widget _buildWebTable(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: columns,
          rows: rows,
          sortAscending: sortAscending,
          sortColumnIndex: sortColumnIndex,
          columnSpacing: 40,
          dataRowMinHeight: 56,
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).primaryColor.withOpacity(0.1),
          ),
        ),
      ),
    );
  }

  Widget _buildTabletTable(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: columns,
        rows: rows,
        sortAscending: sortAscending,
        sortColumnIndex: sortColumnIndex,
        columnSpacing: 20,
        dataRowMinHeight: 48,
      ),
    );
  }

  Widget _buildMobileCards(BuildContext context) {
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(columns.length, (colIndex) {
                if (colIndex >= row.cells.length) return const SizedBox.shrink();
                
                final column = columns[colIndex];
                final cell = row.cells[colIndex];
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _getColumnLabel(column),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: cell.child,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }

  String _getColumnLabel(DataColumn column) {
    if (column.label is Text) {
      return (column.label as Text).data ?? '';
    }
    return '';
  }
}