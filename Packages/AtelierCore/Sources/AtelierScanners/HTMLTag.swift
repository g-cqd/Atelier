// Port of tree-sitter/tree-sitter-html/src/tag.h at
// 5a5ca8551a179998360b4a4ca2c0f366a35acc03 (v0.23.2).
// MIT License. Copyright (c) 2014 Max Brunsfeld.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

struct HTMLTag: Equatable {
    let type: HTMLTagKind
    let customName: [UInt8]

    static let empty = HTMLTag(type: .end, customName: [])

    private static let typesByName: [String: HTMLTagKind] = [
        "AREA": .area,
        "BASE": .base,
        "BASEFONT": .basefont,
        "BGSOUND": .bgsound,
        "BR": .br,
        "COL": .col,
        "COMMAND": .command,
        "EMBED": .embed,
        "FRAME": .frame,
        "HR": .hr,
        "IMAGE": .image,
        "IMG": .img,
        "INPUT": .input,
        "ISINDEX": .isindex,
        "KEYGEN": .keygen,
        "LINK": .link,
        "MENUITEM": .menuitem,
        "META": .meta,
        "NEXTID": .nextid,
        "PARAM": .param,
        "SOURCE": .source,
        "TRACK": .track,
        "WBR": .wbr,
        "A": .a,
        "ABBR": .abbr,
        "ADDRESS": .address,
        "ARTICLE": .article,
        "ASIDE": .aside,
        "AUDIO": .audio,
        "B": .b,
        "BDI": .bdi,
        "BDO": .bdo,
        "BLOCKQUOTE": .blockquote,
        "BODY": .body,
        "BUTTON": .button,
        "CANVAS": .canvas,
        "CAPTION": .caption,
        "CITE": .cite,
        "CODE": .code,
        "COLGROUP": .colgroup,
        "DATA": .data,
        "DATALIST": .datalist,
        "DD": .dd,
        "DEL": .del,
        "DETAILS": .details,
        "DFN": .dfn,
        "DIALOG": .dialog,
        "DIV": .div,
        "DL": .dl,
        "DT": .dt,
        "EM": .em,
        "FIELDSET": .fieldset,
        "FIGCAPTION": .figcaption,
        "FIGURE": .figure,
        "FOOTER": .footer,
        "FORM": .form,
        "H1": .h1,
        "H2": .h2,
        "H3": .h3,
        "H4": .h4,
        "H5": .h5,
        "H6": .h6,
        "HEAD": .head,
        "HEADER": .header,
        "HGROUP": .hgroup,
        "HTML": .html,
        "I": .i,
        "IFRAME": .iframe,
        "INS": .ins,
        "KBD": .kbd,
        "LABEL": .label,
        "LEGEND": .legend,
        "LI": .li,
        "MAIN": .main,
        "MAP": .map,
        "MARK": .mark,
        "MATH": .math,
        "MENU": .menu,
        "METER": .meter,
        "NAV": .nav,
        "NOSCRIPT": .noscript,
        "OBJECT": .object,
        "OL": .ol,
        "OPTGROUP": .optgroup,
        "OPTION": .option,
        "OUTPUT": .output,
        "P": .p,
        "PICTURE": .picture,
        "PRE": .pre,
        "PROGRESS": .progress,
        "Q": .q,
        "RB": .rb,
        "RP": .rp,
        "RT": .rt,
        "RTC": .rtc,
        "RUBY": .ruby,
        "S": .s,
        "SAMP": .samp,
        "SCRIPT": .script,
        "SECTION": .section,
        "SELECT": .select,
        "SLOT": .slot,
        "SMALL": .small,
        "SPAN": .span,
        "STRONG": .strong,
        "STYLE": .style,
        "SUB": .sub,
        "SUMMARY": .summary,
        "SUP": .sup,
        "SVG": .svg,
        "TABLE": .table,
        "TBODY": .tbody,
        "TD": .td,
        "TEMPLATE": .template,
        "TEXTAREA": .textarea,
        "TFOOT": .tfoot,
        "TH": .th,
        "THEAD": .thead,
        "TIME": .time,
        "TITLE": .title,
        "TR": .tr,
        "U": .u,
        "UL": .ul,
        "VAR": .variable,
        "VIDEO": .video,
        "CUSTOM": .custom
    ]

    private static let typesNotAllowedInParagraphs: Set<HTMLTagKind> = [
        .address,
        .article,
        .aside,
        .blockquote,
        .details,
        .div,
        .dl,
        .fieldset,
        .figcaption,
        .figure,
        .footer,
        .form,
        .h1,
        .h2,
        .h3,
        .h4,
        .h5,
        .h6,
        .header,
        .hr,
        .main,
        .nav,
        .ol,
        .p,
        .pre,
        .section
    ]

    static func forName(_ name: [UInt8]) -> HTMLTag {
        let type = typesByName[String(decoding: name, as: UTF8.self)] ?? .custom
        return HTMLTag(type: type, customName: type == .custom ? name : [])
    }

    var isVoid: Bool { type.rawValue < HTMLTagKind.endOfVoidTags.rawValue }

    func canContain(_ other: HTMLTag) -> Bool {
        let child = other.type
        switch type {
            case .li: return child != .li
            case .dt, .dd: return child != .dt && child != .dd
            case .p: return !Self.typesNotAllowedInParagraphs.contains(child)
            case .colgroup: return child == .col
            case .rb, .rt, .rp: return child != .rb && child != .rt && child != .rp
            case .optgroup: return child != .optgroup
            case .tr: return child != .tr
            case .td, .th: return child != .td && child != .th && child != .tr
            default: return true
        }
    }
}
