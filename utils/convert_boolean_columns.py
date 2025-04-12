def convert_boolean_columns(df, bool_cols, bool_map):
    """Converts boolean columns using a mapping."""
    for col in bool_cols:
        if col in df.columns:
            df[col] = (
                df[col]
                .astype(str)  # Convert to string for consistency
                .str.lower()  # Normalize case
                .map(bool_map)  # Map values to boolean
                .fillna(False)  # Explicitly handle missing values
                .astype(bool)  # Convert to boolean type
            )
    return df