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

enum HTMLTagKind: UInt8 {
    case area
    case base
    case basefont
    case bgsound
    case br
    case col
    case command
    case embed
    case frame
    case hr
    case image
    case img
    case input
    case isindex
    case keygen
    case link
    case menuitem
    case meta
    case nextid
    case param
    case source
    case track
    case wbr
    case endOfVoidTags
    case a
    case abbr
    case address
    case article
    case aside
    case audio
    case b
    case bdi
    case bdo
    case blockquote
    case body
    case button
    case canvas
    case caption
    case cite
    case code
    case colgroup
    case data
    case datalist
    case dd
    case del
    case details
    case dfn
    case dialog
    case div
    case dl
    case dt
    case em
    case fieldset
    case figcaption
    case figure
    case footer
    case form
    case h1
    case h2
    case h3
    case h4
    case h5
    case h6
    case head
    case header
    case hgroup
    case html
    case i
    case iframe
    case ins
    case kbd
    case label
    case legend
    case li
    case main
    case map
    case mark
    case math
    case menu
    case meter
    case nav
    case noscript
    case object
    case ol
    case optgroup
    case option
    case output
    case p
    case picture
    case pre
    case progress
    case q
    case rb
    case rp
    case rt
    case rtc
    case ruby
    case s
    case samp
    case script
    case section
    case select
    case slot
    case small
    case span
    case strong
    case style
    case sub
    case summary
    case sup
    case svg
    case table
    case tbody
    case td
    case template
    case textarea
    case tfoot
    case th
    case thead
    case time
    case title
    case tr
    case u
    case ul
    case variable
    case video
    case custom
    case end
}
