enum WeatherModel: String, CaseIterable, Identifiable, Sendable {
    case icon   = "icon_seamless"
    case gfs    = "gfs_seamless"
    case ecmwf  = "ecmwf_ifs025"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .icon:  return "ICON"
        case .gfs:   return "GFS"
        case .ecmwf: return "ECMWF"
        }
    }
}
