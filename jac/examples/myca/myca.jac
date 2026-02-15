"""Myca Lite to serve as example for Myca in Jaclang"""
import from datetime { datetime }

edge next_epoc {}
edge prev_epoc {}

nd epoc {
    has date: datetime;

    def quantize { }
}

nd life(epoc) {
    def quantize { }
}

nd year(epoc) {
    def quantize { }
}

nd month(epoc) {
    def quantize { }
}

nd week(epoc) {
    def quantize { }
}

nd day(epoc) {
    def quantize { }
}

nd item {
    has title: str;
}
