//! Describes one table the sync engine replicates. Modules declare these; the
//! engine only knows column names and kinds.

use serde_json::Value;

use crate::db::Row;

/// SQLite storage class of a domain column.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// TEXT
    Text,
    /// INTEGER (JSON integer)
    Integer,
    /// REAL (any JSON number)
    Real,
}

impl Kind {
    fn describe(self) -> &'static str {
        match self {
            Self::Text => "a string",
            Self::Integer => "an integer",
            Self::Real => "a number",
        }
    }
}

/// One domain column.
#[derive(Debug, Clone, Copy)]
pub struct Column {
    /// SQL column name.
    pub name: &'static str,
    /// Storage class.
    pub kind: Kind,
    /// `true` → NULL/missing is a validation error.
    pub required: bool,
}

impl Column {
    /// TEXT column.
    pub const fn text(name: &'static str, required: bool) -> Self {
        Self {
            name,
            kind: Kind::Text,
            required,
        }
    }
    /// INTEGER column.
    pub const fn integer(name: &'static str, required: bool) -> Self {
        Self {
            name,
            kind: Kind::Integer,
            required,
        }
    }
    /// REAL column.
    pub const fn real(name: &'static str, required: bool) -> Self {
        Self {
            name,
            kind: Kind::Real,
            required,
        }
    }
}

/// Columns every synced table has, in bind order.
pub const BASE_COLUMNS: [&str; 4] = ["id", "updated_at", "deleted_at", "seq"];

/// A synced table: name, domain columns (bind order) and domain validation.
pub struct SyncTable {
    /// SQL table name.
    pub name: &'static str,
    /// Domain columns; base columns are implicit.
    pub columns: &'static [Column],
    /// Domain rules beyond type/presence checks; returns messages.
    pub validate: fn(&Row) -> Vec<String>,
}

impl SyncTable {
    /// Base + type + presence checks, then the table's own rules (only when the
    /// generic checks pass, so domain rules can trust the types).
    pub fn check(&self, row: &Row) -> Vec<String> {
        let mut errors = Vec::new();
        match row.get("id") {
            Some(Value::String(s)) if !s.trim().is_empty() => {}
            _ => errors.push("id must be a non-empty string".to_owned()),
        }
        if !is_non_negative_int(row.get("updated_at")) {
            errors.push("updated_at must be a non-negative integer".to_owned());
        }
        if let Some(v) = row.get("deleted_at")
            && !v.is_null()
            && !is_non_negative_int(Some(v))
        {
            errors.push("deleted_at must be null or a non-negative integer".to_owned());
        }
        for col in self.columns {
            match row.get(col.name) {
                None | Some(Value::Null) => {
                    if col.required {
                        errors.push(format!("{} is required", col.name));
                    }
                }
                Some(v) if !matches_kind(v, col.kind) => {
                    errors.push(format!("{} must be {}", col.name, col.kind.describe()));
                }
                Some(_) => {}
            }
        }
        if errors.is_empty() {
            errors.extend((self.validate)(row));
        }
        errors
    }
}

fn is_non_negative_int(v: Option<&Value>) -> bool {
    v.and_then(Value::as_i64).is_some_and(|n| n >= 0)
}

fn matches_kind(v: &Value, kind: Kind) -> bool {
    match kind {
        Kind::Text => v.is_string(),
        Kind::Integer => v.is_i64(),
        Kind::Real => v.is_number(),
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::unwrap_used)]
    use super::*;
    use serde_json::json;

    const COLS: [Column; 3] = [
        Column::text("name", true),
        Column::integer("reps", true),
        Column::real("weight_kg", false),
    ];

    fn table() -> SyncTable {
        SyncTable {
            name: "t",
            columns: &COLS,
            validate: |row| {
                if row.get("reps").and_then(Value::as_i64) == Some(0) {
                    vec!["reps must be positive".to_owned()]
                } else {
                    Vec::new()
                }
            },
        }
    }

    #[allow(clippy::needless_pass_by_value)]
    fn row(v: Value) -> Row {
        v.as_object().unwrap().clone()
    }

    #[test]
    fn valid_row_passes() {
        let r =
            row(json!({ "id": "a", "updated_at": 5, "deleted_at": null, "name": "x", "reps": 3 }));
        assert!(table().check(&r).is_empty());
    }

    #[test]
    fn reports_base_column_problems() {
        let r = row(
            json!({ "id": "", "updated_at": -1, "deleted_at": "soon", "name": "x", "reps": 3 }),
        );
        let errors = table().check(&r);
        assert_eq!(errors.len(), 3, "{errors:?}");
    }

    #[test]
    fn reports_missing_required_and_wrong_types() {
        let r = row(json!({ "id": "a", "updated_at": 1, "reps": "many", "weight_kg": "heavy" }));
        let errors = table().check(&r);
        assert!(errors.contains(&"name is required".to_owned()));
        assert!(errors.contains(&"reps must be an integer".to_owned()));
        assert!(errors.contains(&"weight_kg must be a number".to_owned()));
    }

    #[test]
    fn domain_rules_run_only_when_types_are_valid() {
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": 0 }));
        assert_eq!(table().check(&r), vec!["reps must be positive".to_owned()]);
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": "0" }));
        assert!(
            !table()
                .check(&r)
                .contains(&"reps must be positive".to_owned())
        );
    }

    #[test]
    fn integer_column_rejects_float_and_accepts_real_for_ints() {
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": 2.5 }));
        assert!(
            table()
                .check(&r)
                .contains(&"reps must be an integer".to_owned())
        );
        let r = row(json!({ "id": "a", "updated_at": 1, "name": "x", "reps": 2, "weight_kg": 60 }));
        assert!(table().check(&r).is_empty());
    }
}
