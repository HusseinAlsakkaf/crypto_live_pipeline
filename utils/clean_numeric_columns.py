import pandas as pd
from decimal import Decimal, InvalidOperation
import logging

def clean_numeric_columns(df, numeric_cols):
    """Converts numeric columns to Decimal for precision without worrying about trailing zeros."""
    for col in numeric_cols:
        if col in df.columns:
            # Convert to Decimal for high precision
            def convert_value(x):
                try:
                    if pd.isna(x) or str(x).strip() in [ ' ', "",'', 'None', 'nan']:
                        return None  # Use None for missing values
                    return Decimal(str(x))  # Convert to Decimal
                except (InvalidOperation, TypeError, ValueError) as e:
                    logging.warning(f"Invalid value '{x}' in column '{col}': {str(e)}")
                    return None  # Handle invalid inputs
            
            df[col] = df[col].apply(convert_value)
    
    return df