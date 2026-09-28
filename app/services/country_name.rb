# Upwork returns a client's country as a full name for most postings and an
# ISO 3166-1 alpha-3 code for the rest: 1,378 of 8,145 rows, 17%, arrive as
# "USA", "GBR", "ITA". Same field, two formats, so the inbox showed a mix of
# "United States" and "USA" rows.
#
# Covers every code observed in the live data. Anything unrecognised is handed
# back unchanged, which is the right failure: a raw code beats a blank.
module CountryName
  CODES = {
    "USA" => "United States", "GBR" => "United Kingdom", "AUS" => "Australia",
    "CAN" => "Canada", "IND" => "India", "ARE" => "United Arab Emirates",
    "NLD" => "Netherlands", "PAK" => "Pakistan", "NGA" => "Nigeria",
    "DEU" => "Germany", "SGP" => "Singapore", "UKR" => "Ukraine",
    "FRA" => "France", "SAU" => "Saudi Arabia", "ZAF" => "South Africa",
    "ESP" => "Spain", "CHE" => "Switzerland", "COL" => "Colombia",
    "HKG" => "Hong Kong", "DNK" => "Denmark", "POL" => "Poland",
    "ISR" => "Israel", "NZL" => "New Zealand", "EGY" => "Egypt",
    "LTU" => "Lithuania", "ITA" => "Italy", "IRL" => "Ireland",
    "MAR" => "Morocco", "SWE" => "Sweden", "IDN" => "Indonesia",
    "BGD" => "Bangladesh", "LKA" => "Sri Lanka", "NOR" => "Norway",
    "ETH" => "Ethiopia", "CYP" => "Cyprus", "PRT" => "Portugal",
    "KWT" => "Kuwait", "LBN" => "Lebanon", "TUR" => "Turkey",
    "MEX" => "Mexico", "BRA" => "Brazil", "ROU" => "Romania",
    "PHL" => "Philippines", "TZA" => "Tanzania", "KEN" => "Kenya",
    "EST" => "Estonia", "AZE" => "Azerbaijan", "CZE" => "Czechia",
    "FIN" => "Finland", "QAT" => "Qatar", "VNM" => "Vietnam",
    "BWA" => "Botswana", "UGA" => "Uganda", "JOR" => "Jordan",
    "KAZ" => "Kazakhstan", "BHR" => "Bahrain", "BEL" => "Belgium",
    "SRB" => "Serbia", "AUT" => "Austria", "THA" => "Thailand",
    "TWN" => "Taiwan", "BHS" => "Bahamas", "OMN" => "Oman",
    "BRB" => "Barbados", "MYS" => "Malaysia", "MTQ" => "Martinique",
    "MNE" => "Montenegro", "MAF" => "Saint Martin", "LVA" => "Latvia",
    "KOR" => "South Korea", "KNA" => "Saint Kitts and Nevis",
    "JAM" => "Jamaica", "HUN" => "Hungary", "HRV" => "Croatia",
    "GRC" => "Greece", "GEO" => "Georgia"
  }.freeze

  def self.call(value)
    text = value.to_s.strip
    return nil if text.empty?

    CODES.fetch(text.upcase, text)
  end
end
