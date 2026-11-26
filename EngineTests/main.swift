import Foundation
let a = LyricParser.parse("[00:10.00][00:35.00]hello\n[offset:500]")
precondition(a.count == 2 && a[0].time == 9.5 && a[1].time == 34.5 && a.allSatisfy { $0.text == "hello" })
let b = LyricParser.parse("[offset:-1000]\n[00:00.1]a\n[00:01.123]b")
precondition(abs(b[0].time - 1.1) < 0.00001 && abs(b[1].time - 2.123) < 0.00001)
precondition(LyricParser.parse("[ar:test]\ninvalid").isEmpty)
print("LRC tests passed")
