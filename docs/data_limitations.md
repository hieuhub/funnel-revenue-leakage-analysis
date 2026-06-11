# Data Limitations

This project uses the GA4 obfuscated sample e-commerce dataset from BigQuery Public Datasets.

Limitations:
- The dataset is obfuscated and should be treated as sample analytics data, not exact company financial reporting.
- Some fields contain NULL, empty string, or placeholder values.
- Product, revenue, and traffic-source analysis should be interpreted as a simulated business case.
- Findings are not official Google Merchandise Store business conclusions.

## Data Quality Notes

- Some traffic source and medium values are grouped as `<Other>` or `(data deleted)`.
- Product categories are inconsistent across item records and require standardization.
- Purchase event count is higher than unique transaction count, so transaction-level revenue will be used carefully.
- Purchase revenue contains null values for some purchase events.