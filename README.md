# Gravity Bookstore Data Warehouse

An MSc Data Science and Artificial Intelligence project at the University of Liverpool. I built a SQL Server data warehouse and Power BI report to analyse monthly order trends, delivery destinations, and demand for non-English books.

## Warehouse design

I used SSIS to extract operational data and customer survey responses into 12 staging tables, then transformed and loaded the data into a star schema. The central `FactOrderLine` table stores one row per order line and connects to five dimensions.

## Data quality

I checked for missing and duplicate source identifiers, unmatched records, and invalid prices. After loading, I reconciled staging and warehouse totals. The warehouse contained 15,400 order lines across 7,550 distinct orders. Three orders with missing status history were retained under an unknown status.

## Dashboard findings

The Power BI report tracked 1,739 ordering customers and showed cancelled and returned orders separately. China and Indonesia led by delivery order volume. The report also tracked demand for non-English books, with Middle English and multilingual titles reported separately.

<img width="1003" height="558" alt="image" src="https://github.com/user-attachments/assets/40ffcbc2-33a6-442d-b4e6-6592a77c431b" />

<img width="996" height="551" alt="image" src="https://github.com/user-attachments/assets/b1485731-e525-4ab6-8f64-645a0a0b36ca" />

<img width="1005" height="566" alt="image" src="https://github.com/user-attachments/assets/167ec655-dd2e-49e2-a0ae-33543738e91f" />

## Explore the project

- [Warehouse schema diagrams](Gravity_Final_Schema_Diagrams.drawio.pdf)
- [SSIS workflow diagrams](Cynthia_Anumba_Gravity_ETL_Process_Diagrams_Final.drawio.pdf)
- [Fact preparation and validation SQL](06_Prepare_FactOrderLine.sql)
- [Power BI report](Gravity_Bookstore_Marketing.pbix)
- 

